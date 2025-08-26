pragma solidity ^0.8.0;

import {IProposalValidator} from "../interfaces/IProposalValidator.sol";
import {ILendoraGovernance} from "../interfaces/ILendoraGovernance.sol";
import {IGovernanceStrategy} from "../interfaces/IGovernanceStrategy.sol";

contract ProposalValidator is IProposalValidator {
      // 提案阈值 - 提交提案所需的最小供应量百分比
  uint256 public immutable override PROPOSITION_THRESHOLD;
  
  // 投票持续时间 - 投票期的区块数
  uint256 public immutable override VOTING_DURATION;
  
  // 投票差异 - 为了使提案通过，"支持"票需要超过"反对"票的供应量百分比
  uint256 public immutable override VOTE_DIFFERENTIAL;
  
  // 最低法定人数 - 提案通过所需的"支持"投票权力的最小供应量百分比
  uint256 public immutable override MINIMUM_QUORUM;
  
  // 精度常量 - 相当于100%，但按精度缩放
  uint256 public constant override ONE_HUNDRED_WITH_PRECISION = 10000;


  /**
   * @dev 构造函数
   * @param propositionThreshold 提交提案所需的最小供应量百分比（以ONE_HUNDRED_WITH_PRECISION为单位）
   * @param votingDuration 投票期的区块数
   * @param voteDifferential 为了使提案通过，"支持"票需要超过"反对"票的供应量百分比（以ONE_HUNDRED_WITH_PRECISION为单位）
   * @param minimumQuorum 提案通过所需的"支持"投票权力的最小供应量百分比（以ONE_HUNDRED_WITH_PRECISION为单位）
   **/
  constructor(
    uint256 propositionThreshold,
    uint256 votingDuration,
    uint256 voteDifferential,
    uint256 minimumQuorum
  ) {
    PROPOSITION_THRESHOLD = propositionThreshold;
    VOTING_DURATION = votingDuration;
    VOTE_DIFFERENTIAL = voteDifferential;
    MINIMUM_QUORUM = minimumQuorum;
  }

        /**
    * @dev 验证提案时调用（例如在治理中创建新提案时）
    * @param governance 治理合约
    * @param user 提案创建者地址
    * @param blockNumber 进行测试的区块号（例如提案创建区块-1）
    * @return 如果可以创建则为true
    **/
    function validateCreatorOfProposal(
        ILendoraGovernance governance,
        address user,
        uint256 blockNumber
    ) external view override returns (bool) {
        return isPropositionPowerEnough(governance, user, blockNumber);
    }


        /**
    * @dev 验证提案取消时调用
    * 需要创建者失去提案权力阈值
    * @param governance 治理合约
    * @param user 提案创建者地址
    * @param blockNumber 进行测试的区块号（例如提案创建区块-1）
    * @return 如果可以取消则为true
    **/
    function validateProposalCancellation(
        ILendoraGovernance
        governance,
        address user,
        uint256 blockNumber
    ) external view override returns (bool) {
        return !isPropositionPowerEnough(governance, user, blockNumber);
    }


    function isProposalPassed(
        ILendoraGovernance governance,
        uint256 proposalId
    ) external view override returns (bool) {
        return (isQuorumReached(governance, proposalId) && 
            isVoteDifferentialReached(governance, proposalId)); 
    }


        /**
    * @dev 返回用户是否有足够的提案权力来创建提案
    * @param governance 治理合约
    * @param user 要挑战的用户地址
    * @param blockNumber 进行挑战的区块号
    * @return 如果用户有足够权力则为true
    **/
    function isPropositionPowerEnough(
        ILendoraGovernance governance,
        address user,
        uint256 blockNumber
    ) public view override returns (bool) {
        // 获取当前的治理策略
        IGovernanceStrategy currentGovernanceStrategy = IGovernanceStrategy(
        governance.getGovernanceStrategy()
        );
        
        // 检查用户的提案权力是否大于等于所需的最小提案权力
        return
        currentGovernanceStrategy.getPropositionPowerAt(user, blockNumber) >=
        getMinimumPropositionPowerNeeded(governance, blockNumber);
    }

    function getMinimumPropositionPowerNeeded(
        ILendoraGovernance governance,
        uint256 blockNumber
    ) public view returns (uint256) {

          // 获取当前的治理策略
    IGovernanceStrategy currentGovernanceStrategy = IGovernanceStrategy(
      governance.getGovernanceStrategy()
    );

        return (
            (currentGovernanceStrategy.getTotalPropositionSupplyAt(blockNumber) * PROPOSITION_THRESHOLD) /
            ONE_HUNDRED_WITH_PRECISION
        );
    }




    function isQuorumReached(
        ILendoraGovernance governance,
        uint256 proposalId
    ) public view returns (bool) {
        ILendoraGovernance.ProposalWithoutVotes memory proposal = governance.getProposalById(proposalId);

        uint256 votingSupply = IGovernanceStrategy(proposal.strategy).getTotalVotingSupplyAt(proposal.startBlock);

        return proposal.forVotes >= getMinimumVotingPowerNeeded(votingSupply);
    }

    function getMinimumVotingPowerNeeded(
        uint256 votingSupply
    ) public view returns (uint256) {
        return (votingSupply * MINIMUM_QUORUM) / ONE_HUNDRED_WITH_PRECISION;
    }

    /**
    * @dev 检查提案是否有足够的"支持"票超过"反对"票
    * 支持票 - 反对票 > 投票差异 * 投票供应量
    * @param governance 治理合约
    * @param proposalId 要验证的提案ID
    * @return 如果有足够的"支持"票则为true
    **/
    function isVoteDifferentialReached(
        ILendoraGovernance governance,
        uint256 proposalId
    ) public view returns (bool) {
        ILendoraGovernance.ProposalWithoutVotes memory proposal = governance.getProposalById(proposalId);

        uint256 votingSupply = IGovernanceStrategy(proposal.strategy).getTotalVotingSupplyAt(proposal.startBlock);

        return proposal.forVotes * ONE_HUNDRED_WITH_PRECISION / votingSupply >= proposal.againstVotes * ONE_HUNDRED_WITH_PRECISION / votingSupply + VOTE_DIFFERENTIAL;
    }

}