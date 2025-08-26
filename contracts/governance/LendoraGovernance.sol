pragma solidity ^0.8.0;

import {ILendoraGovernance} from "../interfaces/ILendoraGovernance.sol";
import {IProposalValidator} from "../interfaces/IProposalValidator.sol";
import {IExecutorWithTimelock} from "../interfaces/IExecutorWithTimelock.sol";
import {IGovernanceStrategy} from "../interfaces/IGovernanceStrategy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LendoraGovernance is Ownable,ILendoraGovernance {

    //====状态变量====
    // 治理策略合约地址 - 用于计算投票权力和提案权力
    address private _governanceStrategy;

      // 投票延迟 - 提案创建后到开始投票的区块数
    uint256 private _votingDelay;

      // 提案总数计数器
    uint256 private _proposalsCount;

      // 提案ID到提案详情的映射
    mapping(uint256 => Proposal) private _proposals;

      // 已授权的执行器地址映射
    mapping(address => bool) private _authorizedExecutors;

    address private _guardian;

      // 合约名称常量
    string public constant NAME = 'Lendora Governance';

    // ====EIP712 常量====
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
      'EIP712Domain(string name,uint256 chainId,address verifyingContract)'
    );

    bytes32 public constant VOTE_EMITTED_TYPEHASH = keccak256(
      'VoteEmitted(uint256 id,bool support)'
    );

    function getChainId() public view returns (uint256) {
      return block.chainid;
    }

    //====函数修饰器====
    modifier onlyGuardian() {
      require(msg.sender == _guardian, 'ONLY_GUARDIAN');
      _;
    }
    
    // ====构造函数====
    constructor(
        address governanceStrategy,
        uint256 votingDelay,
        address guardian,
        address[] memory executors
    ) {
        _setGovernanceStrategy(governanceStrategy);
        _setVotingDelay(votingDelay);
        _guardian = guardian;
        authorizeExecutors(executors);
    }


    //==== 提案生命周期（Create / Cancel / Queue / Execute）====
    // ====创建提案时使用的临时变量结构体====
    struct CreateVars {
        uint256 startBlock;        // 投票开始区块
        uint256 endBlock;          // 投票结束区块
        uint256 previousProposalsCount; // 之前的提案总数
    }

    function create(
        IExecutorWithTimelock executor,
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        bool[] memory withDelegatecalls,
        bytes32 ipfsHash
    ) external override returns (uint256) {
        // 验证目标地址不能为空
        require(targets.length != 0, 'INVALID_EMPTY_TARGETS');
            // 验证所有数组长度必须一致
        require(
            targets.length == values.length &&
            targets.length == signatures.length &&
            targets.length == calldatas.length &&
            targets.length == withDelegatecalls.length,
            'INCONSISTENT_PARAMS_LENGTH'
        );

        require(isExecutorAuthorized(address(executor)), 'EXECUTOR_NOT_AUTHORIZED');

        require(
          IProposalValidator(address(executor)).validateCreatorOfProposal(
            ILendoraGovernance(address(this)),
            msg.sender,
            block.number - 1
          ),
          'PROPOSITION_CREATION_INVALID'
        );

        CreateVars memory vars;

        vars.startBlock = block.number + _votingDelay;

        vars.endBlock = vars.startBlock + IProposalValidator(address(executor)).VOTING_DURATION();

        vars.previousProposalsCount = _proposalsCount;
        Proposal storage newProposal = _proposals[vars.previousProposalsCount];

        newProposal.id = vars.previousProposalsCount;
        newProposal.creator = msg.sender;
        newProposal.executor = executor;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.withDelegatecalls = withDelegatecalls;
        newProposal.startBlock = vars.startBlock;
        newProposal.endBlock = vars.endBlock;
        newProposal.strategy = _governanceStrategy;
        newProposal.ipfsHash = ipfsHash;

        _proposalsCount++;

    // 触发提案创建事件
        emit ProposalCreated(
          vars.previousProposalsCount,
          msg.sender,
          executor,
          targets,
          values,
          signatures,
          calldatas,
          withDelegatecalls,
          vars.startBlock,
          vars.endBlock,
          _governanceStrategy,
          ipfsHash
        );

      return newProposal.id;
   }


      //取消提案
      function cancel(uint256 proposalId) external override {

        ProposalState state = getProposalState(proposalId);

            // 只能取消未执行、未取消、未过期的提案
            require(
              state != ProposalState.Executed &&
                state != ProposalState.Cancelled &&
                state != ProposalState.Expired,
              'ONLY_BEFORE_EXECUTED'
        );


        Proposal storage proposal = _proposals[proposalId];

        // 只有守护者或满足取消条件的用户才能取消
          require(
            msg.sender == _guardian ||
              IProposalValidator(address(proposal.executor)).validateProposalCancellation(
                this,
                proposal.creator,
                block.number - 1
              ),
            'PROPOSITION_CANCELLATION_INVALID'
          );


          // 标记提案为已取消
          proposal.cancelled = true;


                    // 取消执行器中的所有交易
          for (uint256 i = 0; i < proposal.targets.length; i++) {
            proposal.executor.cancelTransaction(
              proposal.targets[i],
              proposal.values[i],
              proposal.signatures[i],
              proposal.calldatas[i],
              proposal.executionTime,
              proposal.withDelegatecalls[i]
            );
          }

          emit ProposalCancelled(proposalId);

      } 


        /**
   * @dev 排队提案（如果提案成功）
   * @param proposalId 要排队的提案ID
   **/
  function queue(uint256 proposalId) external override {
    // 只有成功的提案才能排队
    require(getProposalState(proposalId) == ProposalState.Succeeded, 'INVALID_STATE_FOR_QUEUE');
    Proposal storage proposal = _proposals[proposalId];
    
    // 计算执行时间：当前时间 + 执行器延迟
    uint256 executionTime = block.timestamp + proposal.executor.getDelay();
    
    // 将所有交易排队到执行器
    for (uint256 i = 0; i < proposal.targets.length; i++) {
      _queueOrRevert(
        proposal.executor,
        proposal.targets[i],
        proposal.values[i],
        proposal.signatures[i],
        proposal.calldatas[i],
        executionTime,
        proposal.withDelegatecalls[i]
      );
    }
    proposal.executionTime = executionTime;

    emit ProposalQueued(proposalId, executionTime, msg.sender);
  }


  /**
   * @dev 执行提案（如果提案已排队）
   * @param proposalId 要执行的提案ID
   **/
  function execute(uint256 proposalId) external payable override {
    // 只有已排队的提案才能执行
    require(getProposalState(proposalId) == ProposalState.Queued, 'ONLY_QUEUED_PROPOSALS');
    Proposal storage proposal = _proposals[proposalId];
    proposal.executed = true;
    
    // 执行所有交易
    for (uint256 i = 0; i < proposal.targets.length; i++) {
      proposal.executor.executeTransaction{value: proposal.values[i]}(
        proposal.targets[i],
        proposal.values[i],
        proposal.signatures[i],
        proposal.calldatas[i],
        proposal.executionTime,
        proposal.withDelegatecalls[i]
      );
    }
    emit ProposalExecuted(proposalId, msg.sender);
  }


  //==== 投票（Submit Votes）====
  /**
   * @dev 允许msg.sender对提案进行投票的函数
   * @param proposalId 提案ID
   * @param support 布尔值，true = 支持，false = 反对
   **/
  function submitVote(uint256 proposalId, bool support) external override {
    return _submitVote(msg.sender, proposalId, support);
  }

  /**
   * @dev 注册通过签名离线投票的用户投票的函数
   * @param proposalId 提案ID
   * @param support 布尔值，true = 支持，false = 反对
   * @param v 投票者签名的v部分
   * @param r 投票者签名的r部分
   * @param s 投票者签名的s部分
   **/
  function submitVoteBySignature(
    uint256 proposalId,
    bool support,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external override {
    // 计算EIP-712签名哈希
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), getChainId(), address(this))),
        keccak256(abi.encode(VOTE_EMITTED_TYPEHASH, proposalId, support))
      )
    );
    // 恢复签名者地址
    address signer = ecrecover(digest, v, r, s);
    require(signer != address(0), 'INVALID_SIGNATURE');
    return _submitVote(signer, proposalId, support);
  }
  //==== 配置（Setters / Admin）====
    /**
   * @dev 设置新的治理策略
   * 注意：owner应该是一个时间锁执行器，所以需要通过提案来设置
   * @param governanceStrategy 新的治理策略合约地址
   **/
  function setGovernanceStrategy(address governanceStrategy) external override onlyOwner {
    _setGovernanceStrategy(governanceStrategy);
  }

  /**
   * @dev 设置新的投票延迟（新创建的提案可以投票前的延迟）
   * 注意：owner应该是一个时间锁执行器，所以需要通过提案来设置
   * @param votingDelay 新的投票延迟（区块数）
   **/
  function setVotingDelay(uint256 votingDelay) external override onlyOwner {
    _setVotingDelay(votingDelay);
  }

  /**
   * @dev 向授权执行器列表添加新地址
   * @param executors 要授权的新地址列表
   **/
  function authorizeExecutors(address[] memory executors) public override onlyOwner {
    for (uint256 i = 0; i < executors.length; i++) {
      _authorizeExecutor(executors[i]);
    }
  }

  /**
   * @dev 从授权执行器列表中移除地址
   * @param executors 要移除授权的地址列表
   **/
  function unauthorizeExecutors(address[] memory executors) public override onlyOwner {
    for (uint256 i = 0; i < executors.length; i++) {
      _unauthorizeExecutor(executors[i]);
    }
  }

  /**
   * @dev 让守护者放弃其特权
   **/
  function __abdicate() external override onlyGuardian {
    _guardian = address(0);
  }

  //==== 查询（Getters）====
  /**
   * @dev 获取当前治理策略地址的getter
   * @return 当前治理策略合约的地址
   **/
  function getGovernanceStrategy() external view override returns (address) {
    return _governanceStrategy;
  }

  /**
   * @dev 获取当前投票延迟的getter（创建提案后可以投票前的延迟）
   * 与投票持续时间不同
   * @return 投票延迟的区块数
   **/
  function getVotingDelay() external view override returns (uint256) {
    return _votingDelay;
  }

  /**
   * @dev 返回地址是否为授权执行器
   * @param executor 要评估为授权执行器的地址
   * @return 如果已授权则为true
   **/
  function isExecutorAuthorized(address executor) public view override returns (bool) {
    return _authorizedExecutors[executor];
  }

  /**
   * @dev 获取守护者地址的getter，守护者主要可以取消提案
   * @return 守护者的地址
   **/
  function getGuardian() external view override returns (address) {
    return _guardian;
  }

  /**
   * @dev 获取提案计数的getter（迄今为止创建的提案总数）
   * @return 提案计数
   **/
  function getProposalsCount() external view override returns (uint256) {
    return _proposalsCount;
  }

  /**
   * @dev 通过ID获取提案的getter
   * @param proposalId 要获取的提案ID
   * @return 作为ProposalWithoutVotes内存对象的提案
   **/
  function getProposalById(uint256 proposalId)
    external
    view
    override
    returns (ProposalWithoutVotes memory)
  {
    Proposal storage proposal = _proposals[proposalId];
    ProposalWithoutVotes memory proposalWithoutVotes = ProposalWithoutVotes({
      id: proposal.id,
      creator: proposal.creator,
      executor: proposal.executor,
      targets: proposal.targets,
      values: proposal.values,
      signatures: proposal.signatures,
      calldatas: proposal.calldatas,
      withDelegatecalls: proposal.withDelegatecalls,
      startBlock: proposal.startBlock,
      endBlock: proposal.endBlock,
      executionTime: proposal.executionTime,
      forVotes: proposal.forVotes,
      againstVotes: proposal.againstVotes,
      executed: proposal.executed,
      cancelled: proposal.cancelled,
      strategy: proposal.strategy,
      ipfsHash: proposal.ipfsHash
    });

    return proposalWithoutVotes;
  }

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
    override
    returns (Vote memory)
  {
    return _proposals[proposalId].votes[voter];
  }

  /**
   * @dev 获取提案的当前状态
   * @param proposalId 提案ID
   * @return 提案的当前状态
   **/
  function getProposalState(uint256 proposalId) public view override returns (ProposalState) {
    require(_proposalsCount >= proposalId, 'INVALID_PROPOSAL_ID');
    Proposal storage proposal = _proposals[proposalId];
    if (proposal.cancelled) {
      return ProposalState.Cancelled;
    } else if (block.number <= proposal.startBlock) {
      return ProposalState.Pending;
    } else if (block.number <= proposal.endBlock) {
      return ProposalState.Active;
    } else if (!IProposalValidator(address(proposal.executor)).isProposalPassed(this, proposalId)) {
      return ProposalState.Failed;
    } else if (proposal.executionTime == 0) {
      return ProposalState.Succeeded;
    } else if (proposal.executed) {
      return ProposalState.Executed;
    } else if (proposal.executor.isProposalOverGracePeriod(this, proposalId)) {
      return ProposalState.Expired;
    } else {
      return ProposalState.Queued;
    }
  }

  //==== 内部方法（Internal Helpers）====
  /**
   * @dev 内部函数：排队交易或回滚（如果已存在）
   * @param executor 执行器合约
   * @param target 目标地址
   * @param value 交易值
   * @param signature 函数签名
   * @param callData 调用数据
   * @param executionTime 执行时间
   * @param withDelegatecall 是否使用delegatecall
   **/
  function _queueOrRevert(
    IExecutorWithTimelock executor,
    address target,
    uint256 value,
    string memory signature,
    bytes memory callData,
    uint256 executionTime,
    bool withDelegatecall
  ) internal {
    // 检查交易是否已经排队
    require(
      !executor.isActionQueued(
        keccak256(abi.encode(target, value, signature, callData, executionTime, withDelegatecall))
      ),
      'DUPLICATED_ACTION'
    );
    // 排队交易
    executor.queueTransaction(target, value, signature, callData, executionTime, withDelegatecall);
  }

  /**
   * @dev 内部函数：提交投票
   * @param voter 投票者地址
   * @param proposalId 提案ID
   * @param support 是否支持
   **/
  function _submitVote(
    address voter,
    uint256 proposalId,
    bool support
  ) internal {
    // 只有活跃状态的提案才能投票
    require(getProposalState(proposalId) == ProposalState.Active, 'VOTING_CLOSED');
    Proposal storage proposal = _proposals[proposalId];
    Vote storage vote = proposal.votes[voter];

    // 每个地址只能投票一次
    require(vote.votingPower == 0, 'VOTE_ALREADY_SUBMITTED');

    // 获取投票者在提案开始区块的投票权力
    uint256 votingPower = IGovernanceStrategy(proposal.strategy).getVotingPowerAt(
      voter,
      proposal.startBlock
    );

    // 根据支持情况增加相应的投票数
    if (support) {
      proposal.forVotes = proposal.forVotes + votingPower;
    } else {
      proposal.againstVotes = proposal.againstVotes + votingPower;
    }

    // 记录投票信息
    vote.support = support;
    vote.votingPower = uint248(votingPower);

    emit VoteEmitted(proposalId, voter, support, votingPower);
  }

  /**
   * @dev 内部函数：设置治理策略
   * @param governanceStrategy 新的治理策略地址
   **/
  function _setGovernanceStrategy(address governanceStrategy) internal {
    _governanceStrategy = governanceStrategy;

    emit GovernanceStrategyChanged(governanceStrategy, msg.sender);
  }

  /**
   * @dev 内部函数：设置投票延迟
   * @param votingDelay 新的投票延迟
   **/
  function _setVotingDelay(uint256 votingDelay) internal {
    _votingDelay = votingDelay;

    emit VotingDelayChanged(votingDelay, msg.sender);
  }

  /**
   * @dev 内部函数：授权执行器
   * @param executor 执行器地址
   **/
  function _authorizeExecutor(address executor) internal {
    _authorizedExecutors[executor] = true;
    emit ExecutorAuthorized(executor);
  }

  /**
   * @dev 内部函数：取消授权执行器
   * @param executor 执行器地址
   **/
  function _unauthorizeExecutor(address executor) internal {
    _authorizedExecutors[executor] = false;
    emit ExecutorUnauthorized(executor);
  }




}



