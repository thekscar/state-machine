pragma solidity 0.4.19;


/// @title A library for implementing a generic state machine pattern.
library StateMachineLib {

    event LogTransition(bytes32 indexed stageId, uint256 blockNumber);

    struct Stage {
        // The id of the next stage
        bytes32 nextId;

        // The identifiers for the available functions in each stage
        mapping(bytes4 => bool) allowedFunctions;

        function() internal[] transitionCallbacks;
        function(bytes32) internal returns(bool)[] startConditions;
    }

    struct State {
        // The current stage id
        bytes32 currentStageId;

        // Checks if a stage id is valid
        mapping(bytes32 => bool) validStage;

        // Maps stage ids to their Stage structs
        mapping(bytes32 => Stage) stages;
    }

    /// @dev Creates and sets the initial stage. It has to be called before creating any transitions.
    /// @param stageId The id of the (new) stage to set as initial stage.
    function setInitialStage(State storage self, bytes32 stageId) public {
        require(self.currentStageId == 0);
        self.validStage[stageId] = true;
        self.currentStageId = stageId;
    }

    /// @dev Creates a transition from 'fromId' to 'toId'. If fromId already had a nextId, it deletes the now unreachable stage.
    /// @param fromId The id of the stage from which the transition begins.
    /// @param toId The id of the stage that will be reachable from "fromId".
    function createTransition(State storage self, bytes32 fromId, bytes32 toId) public {
        require(self.validStage[fromId]);

        Stage storage from = self.stages[fromId];

        // Invalidate the stage that won't be reachable any more
        if (from.nextId != 0) {
            self.validStage[from.nextId] = false;
            delete self.stages[from.nextId];
        }

        from.nextId = toId;
        self.validStage[toId] = true;
    }

    /// @dev Creates the given stages.
    /// @param stageIds Array of stage ids.
    function setStages(State storage self, bytes32[] stageIds) public {
        require(stageIds.length > 0);

        setInitialStage(self, stageIds[0]);

        for (uint256 i = 1; i < stageIds.length; i++) {
            createTransition(self, stageIds[i - 1], stageIds[i]);
        }
    }

    /// @dev Goes to the next stage if posible (if the next stage is valid)
    function goToNextStage(State storage self) public {
        Stage storage current = self.stages[self.currentStageId];

        bytes32 nextId = current.nextId;
        require(self.validStage[nextId]);

        self.currentStageId = current.nextId;

        Stage storage next = self.stages[nextId];

        for (uint256 i = 0; i < next.transitionCallbacks.length; i++) {
            next.transitionCallbacks[i]();
        }

        LogTransition(nextId, block.number);
    }

    /// @dev Checks if the a function is allowed in the current stage.
    /// @param selector A function selector (bytes4[keccak256(functionSignature)])
    /// @return true If the function is allowed in the current stage
    function checkAllowedFunction(State storage self, bytes4 selector) public constant returns(bool) {
        return self.stages[self.currentStageId].allowedFunctions[selector];
    }

    /// @dev Allow a function in the given stage.
    /// @param stageId The id of the stage
    /// @param selector A function selector (bytes4[keccak256(functionSignature)])
    function allowFunction(State storage self, bytes32 stageId, bytes4 selector) public {
        require(self.validStage[stageId]);
        self.stages[stageId].allowedFunctions[selector] = true;
    }

    function addStartCondition(State storage self, bytes32 stageId, function(bytes32) internal returns(bool) condition) internal {
        require(self.validStage[stageId]);
        self.stages[stageId].startConditions.push(condition);
    }

    function addCallback(State storage self, bytes32 stageId, function() internal callback) internal {
        require(self.validStage[stageId]);
        self.stages[stageId].transitionCallbacks.push(callback);
    }

    function conditionalTransitions(State storage self) public {

        bytes32 nextId = self.stages[self.currentStageId].nextId;

        while (self.validStage[nextId]) {
            StateMachineLib.Stage storage next = self.stages[nextId];
            // If one of the next stage's condition is true, go to next stage and continue
            bool stageChanged = false;
            for (uint256 i = 0; i < next.startConditions.length; i++) {
                if (next.startConditions[i](nextId)) {
                    goToNextStage(self);
                    nextId = next.nextId;
                    stageChanged = true;
                    break;
                }
            }

            if (!stageChanged) break;
        }
    }
}
