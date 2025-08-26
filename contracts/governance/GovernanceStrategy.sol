pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";
import {IGovernanceStrategy} from "../interfaces/IGovernanceStrategy.sol";
import {IGovernancePowerDelegationToken} from "../interfaces/IGovernancePowerDelegationToken.sol";

contract GovernanceStrategy is IGovernanceStrategy {
    address public immutable  LENDORA_TOKEN;

    address public immutable STK_LENDORA_TOKEN;

    constructor(address lendoraToken, address stkLendoraToken) {
        LENDORA_TOKEN = lendoraToken;
        STK_LENDORA_TOKEN = stkLendoraToken;
    }

    function getTotalPropositionSupplyAt(uint256 blockNumber) public view override returns (uint256) {
        return IERC20(LENDORA_TOKEN).totalSupplyAt(blockNumber);
    }
    
    function getTotalVotingSupplyAt(uint256 blockNumber) public view override returns (uint256) {
        return getTotalPropositionSupplyAt(blockNumber);
    }

    function getPropositionPowerAt(address user, uint256 blockNumber) public view override returns (uint256) {
        return _getPowerByTypeAt(user, blockNumber, IGovernancePowerDelegationToken.DelegationType.PROPOSITION_POWER);
    }

    function getVotingPowerAt(address user, uint256 blockNumber) public view override returns (uint256) {
        return _getPowerByTypeAt(user, blockNumber, IGovernancePowerDelegationToken.DelegationType.VOTING_POWER);
    }


    function _getPowerByTypeAt(
        address user,
        uint256 blockNumber,
        IGovernancePowerDelegationToken.DelegationType delegationType
    ) internal view returns (uint256) {
        return 
        IGovernancePowerDelegationToken(STK_LENDORA_TOKEN).getPowerAtBlock(user, delegationType, blockNumber) + 
        IGovernancePowerDelegationToken(LENDORA_TOKEN).getPowerAtBlock(user,delegationType,blockNumber);
    }

}