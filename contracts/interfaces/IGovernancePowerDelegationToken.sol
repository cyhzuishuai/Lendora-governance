pragma solidity ^0.8.0;

interface IGovernancePowerDelegationToken {
    enum DelegationType {VOTING_POWER, PROPOSITION_POWER}

    function getDelegateeByType(address delegator,DelegationType delegationType) 
        external view returns (address);

    function getPowerCurrent(address user, DelegationType delegationType)
        external view returns (uint256);

    function getPowerAtBlock(address user, DelegationType delegationType, uint256 blockNumber)
        external view returns (uint256);

    function delegateByTypeBySig(
        address delegator,
        DelegationType delegationType,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function delegateBySig(
        address delegator,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    
}