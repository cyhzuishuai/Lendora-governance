pragma solidity ^0.8.0;

import {IExecutorWithTimelock} from "../interfaces/IExecutorWithTimelock.sol";
import {ILendoraGovernance} from "../interfaces/ILendoraGovernance.sol";

contract ExecutorWithTimelock is IExecutorWithTimelock {
    //====状态变量====
    // 宽限期 - 延迟期结束后，提案可以执行的时间窗口
    uint256 public immutable override GRACE_PERIOD;
    
    // 最小延迟时间 - 延迟时间的最小阈值（秒）
    uint256 public immutable override MINIMUM_DELAY;
    
    // 最大延迟时间 - 延迟时间的最大阈值（秒）
    uint256 public immutable override MAXIMUM_DELAY;

    // 管理员地址 - 唯一可以调用主要函数的地址（通常是治理合约）
    address private _admin;
    
    // 待定管理员地址 - 可以成为新管理员的地址
    address private _pendingAdmin;
    
    // 当前延迟时间 - 排队和执行之间的最小时间间隔（秒）
    uint256 private _delay;

    // 已排队交易的映射 - 记录哪些交易已被排队
    mapping(bytes32 => bool) private _queuedTransactions;

    //====构造函数====
    constructor(
        address admin,
        uint256 delay,
        uint256 gracePeriod,
        uint256 minimumDelay,
        uint256 maximumDelay
    ) {
        require(delay >= minimumDelay && delay <= maximumDelay, "INVALID_DELAY");
        _admin = admin;
        _delay = delay;
        GRACE_PERIOD = gracePeriod;
        MINIMUM_DELAY = minimumDelay;
        MAXIMUM_DELAY = maximumDelay;
        emit NewAdmin(admin);
        emit NewDelay(delay);
    }

    //====函数修饰器====
    modifier onlyAdmin() {
        require(msg.sender == _admin, "ONLY_ADMIN");
        _;
    }

    modifier onlyTimelock() {
        require(msg.sender == address(this), "ONLY_TIMELOCK");
        _;
    }

    modifier onlyPendingAdmin() {
        require(msg.sender == _pendingAdmin, "ONLY_PENDING_ADMIN");
        _;
    }

    //====交易排队====
    function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executionTime,
        bool withDelegatecall
    ) public override onlyAdmin returns (bytes32) {
        bytes32 actionHash = keccak256(abi.encode(target, value, signature, data, executionTime, withDelegatecall));
        require(!_queuedTransactions[actionHash], "TRANSACTION_ALREADY_QUEUED");
        _queuedTransactions[actionHash] = true;
        emit QueuedAction(actionHash, target, value, signature, data, executionTime, withDelegatecall);
        return actionHash;
    }

    function cancelTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executionTime,
        bool withDelegatecall
    ) public override onlyAdmin returns (bytes32) {
        // 计算操作哈希
        bytes32 actionHash = keccak256(
        abi.encode(target, value, signature, data, executionTime, withDelegatecall)
        );
        // 标记交易为未排队
        _queuedTransactions[actionHash] = false;

        emit CancelledAction(
        actionHash,
        target,
        value,
        signature,
        data,
        executionTime,
        withDelegatecall
        );
        return actionHash;
    }

    //====交易执行====
    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executionTime,
        bool withDelegatecall
    ) public payable override onlyAdmin returns (bytes memory) {
        bytes32 actionHash = keccak256(abi.encode(target, value, signature, data, executionTime, withDelegatecall));

        require(_queuedTransactions[actionHash], "TRANSACTION_NOT_QUEUED");

        require(block.timestamp >= executionTime, "NOT_EXECUTION_TIME");

        require(block.timestamp <= executionTime + GRACE_PERIOD, "PROPOSAL_OVER_GRACE_PERIOD");

        _queuedTransactions[actionHash] = false;

        bytes memory callData;

        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        bool success;
        bytes memory resultData;

        if(withDelegatecall) {
            require(msg.value >= value, "NOT_ENOUGH_MSG_VALUE");
            (success, resultData) = target.delegatecall(callData);
        } else {
            (success, resultData) = target.call{value: value}(callData);
        }

        require(success, 'FAILED_ACTION_EXECUTION');

        emit ExecutedAction(
            actionHash,
            target,
            value,
            signature,
            data,
            executionTime,
            withDelegatecall,
            resultData
        );

        return resultData;

    }
    //====设置各种权限====

    function setDelay(uint256 newDelay) public onlyTimelock {
        require(newDelay >= MINIMUM_DELAY, 'DELAY_SHORTER_THAN_MINIMUM');
        require(newDelay <= MAXIMUM_DELAY, 'DELAY_LONGER_THAN_MAXIMUM');
        _delay = newDelay;
        emit NewDelay(newDelay);
    }

    function setPendingAdmin(address newPendingAdmin) public onlyAdmin {
        require(newPendingAdmin != address(0), "INVALID_PENDING_ADMIN");
        _pendingAdmin = newPendingAdmin;
    }

    function acceptAdmin() public onlyPendingAdmin {
        _admin = _pendingAdmin;
        _pendingAdmin = address(0);
        emit NewAdmin(_admin);
    }

    //====获取各种权限====
    function getAdmin() public view override returns (address) {
        return _admin;
    }

    function getPendingAdmin() public view override returns (address) {
        return _pendingAdmin;
    }

    function getDelay() public view override returns (uint256) {
        return _delay;
    }

    //====检查各种权限====
    function isActionQueued(bytes32 actionHash) public view override returns (bool) {
        return _queuedTransactions[actionHash];
    }

    function isProposalOverGracePeriod(ILendoraGovernance governance, uint256 proposalId) external view override returns (bool) {
        ILendoraGovernance.ProposalWithoutVotes memory proposal = governance.getProposalById(proposalId);
        return block.timestamp > GRACE_PERIOD + proposal.executionTime;
    }

    receive() external payable {}

}

