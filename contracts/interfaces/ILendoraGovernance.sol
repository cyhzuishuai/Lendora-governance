pragma solidity ^0.8.0;
import {IExecutorWithTimelock} from "./IExecutorWithTimelock.sol";

interface ILendoraGovernance {
  // 提案状态枚举 - 定义提案在其生命周期中的各种状态
  enum ProposalState {
    Pending,    // 待处理 - 提案已创建但投票尚未开始
    Cancelled,   // 已取消 - 提案被取消
    Active,     // 活跃 - 提案正在投票中
    Failed,     // 失败 - 投票结束但提案未通过
    Succeeded,  // 成功 - 投票结束且提案通过
    Queued,     // 已排队 - 提案已排队等待执行
    Expired,    // 已过期 - 提案排队时间超过宽限期
    Executed    // 已执行 - 提案已执行完成
  }

    struct Vote {
        bool support;
        uint248 votingPower;
    }

    struct Proposal {
        uint256 id;
        address creator;
        IExecutorWithTimelock executor;       // 执行器合约
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        bool[] withDelegatecalls;
        uint256 startBlock;
        uint256 endBlock;
        uint256 executionTime;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bool cancelled;
        address strategy;
        bytes32 ipfsHash;
        mapping(address => Vote) votes;
    }


        /**
    * @dev 不包含投票信息的提案结构体 - 用于外部查询
    * 与Proposal结构体相同，但不包含votes映射（因为映射不能在外部函数中返回）
    **/
    struct ProposalWithoutVotes {
        uint256 id;                           // 提案ID
        address creator;                      // 创建者地址
        IExecutorWithTimelock executor;       // 执行器合约
        address[] targets;                    // 目标合约地址数组
        uint256[] values;                     // 交易值数组
        string[] signatures;                  // 函数签名数组
        bytes[] calldatas;                    // 调用数据数组
        bool[] withDelegatecalls;             // delegatecall标志数组
        uint256 startBlock;                   // 投票开始区块
        uint256 endBlock;                     // 投票结束区块
        uint256 executionTime;                // 执行时间
        uint256 forVotes;                     // 支持票数
        uint256 againstVotes;                 // 反对票数
        bool executed;                        // 是否已执行
        bool cancelled;                        // 是否已取消
        address strategy;                     // 治理策略地址
        bytes32 ipfsHash;                     // IPFS哈希
    }

    event ProposalCreated(
        uint256 id,
        address indexed creator,
        IExecutorWithTimelock indexed executor,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        bool[] withDelegatecalls,
        uint256 startBlock,
        uint256 endBlock,
        address strategy,
        bytes32 ipfsHash
    );

    event ProposalCancelled(uint256 id);

    event ProposalQueued(uint256 id, uint256 executionTime, address initiatorQueueing);

    event ProposalExecuted(uint256 id, address initiatorExecution);

    event VoteEmitted(uint256 id, address indexed voter, bool support, uint256 votingPower);

    event GovernanceStrategyChanged(address indexed newStrategy, address indexed initiatorChange);

    event VotingDelayChanged(uint256 newVotingDelay, address indexed initiatorChange);

    event ExecutorAuthorized(address executor);

    event ExecutorUnauthorized(address executor);

    function create(
        IExecutorWithTimelock executor,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        bool[] memory withDelegatecalls,
        bytes32 ipfsHash

    ) external returns (uint256);

    function cancel(uint256 proposalid) external;

    function queue(uint256 proposalid) external;

    function execute(uint256 proposalid) payable external;

    function submitVote(uint256 proposalid, bool support) external;

    function submitVoteBySignature(
        uint256 proposalid,
        bool support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function setGovernanceStrategy(address governanceStrategy) external;


    /**
    * @dev 设置新的投票延迟（新创建的提案可以投票前的延迟）
    * 注意：owner应该是一个时间锁执行器，所以需要通过提案来设置
    * @param votingDelay 新的投票延迟（秒）
    **/
    function setVotingDelay(uint256 votingDelay) external;

        /**
    * @dev 向授权执行器列表添加新地址
    * @param executors 要授权的新地址列表
    **/
    function authorizeExecutors(address[] memory executors) external;

    /**
    * @dev 从授权执行器列表中移除地址
    * @param executors 要移除授权的地址列表
    **/
    function unauthorizeExecutors(address[] memory executors) external;

    function __abdicate() external;

  function getGovernanceStrategy() external view returns (address);

  function getVotingDelay() external view returns (uint256);

    function isExecutorAuthorized(address executor) external view returns (bool);

      function getGuardian() external view returns (address);

        function getProposalsCount() external view returns (uint256);

    function getProposalById(uint256 proposalId) external view returns (ProposalWithoutVotes memory);


      /**
   * @dev 获取投票者关于提案的投票的getter
   * 注意：Vote是一个结构体：({bool support, uint248 votingPower})
   * @param proposalId 提案ID
   * @param voter 投票者地址
   * @return 关联的Vote内存对象
   **/
  function getVoteOnProposal(uint256 proposalId, address voter)
    external
    view
    returns (Vote memory);

    function getProposalState(uint256 proposalId) external view returns (ProposalState);


}
