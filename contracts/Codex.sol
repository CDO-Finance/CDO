// SPDX-License-Identifier: MIT
pragma solidity 0.6.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


// CodexToken interface
interface ICodexToken is IERC20 {
  function cap() external view returns (uint256);
  function unlockedSupply() external view returns (uint256);
  function totalLock() external view returns (uint256);
  function mint(address _to, uint256 _amount) external;
  function burn(address _account, uint256 _amount) external;
  function totalBalanceOf(address _account) external view returns (uint256);
  function lockOf(address _account) external view returns (uint256);
  function lastUnlockBlock(address _account) external view returns (uint256);
  function canUnlockAmount(address _account) external view returns (uint256);
  function unlock() external;
  function lock(address _account, uint256 _amount) external;
  function transferRights(address newOwner) external;
}

// CodexToken with Governance.
contract CodexToken is ERC20("CodexToken", "CODEX"), Ownable, ICodexToken {
  uint256 private _totalLock;
  uint256 private constant MULTIPLIER = 1 ether;
  uint256 private _cap = 18000000 * MULTIPLIER;

  uint256 public endReleaseBlock;
  uint256 public startReleaseBlock;

  mapping(address => uint256) private _locks;
  mapping(address => uint256) private _lastUnlockBlock;

  event Lock(address indexed to, uint256 value);


  //  –––––––––––––––––––––
  //  CONSTRUCTOR
  //  –––––––––––––––––––––


  constructor(address warchestReceiver, address devTimelockReceiver, uint256 _startReleaseBlock, uint256 _endReleaseBlock) public {
    require(_endReleaseBlock > _startReleaseBlock, "endReleaseBlock < startReleaseBlock");

    startReleaseBlock = _startReleaseBlock;
    endReleaseBlock = _endReleaseBlock;

    _setupDecimals(18);
    _mint(warchestReceiver, 900000 * MULTIPLIER); // 0.9 mln tokens
    _mint(devTimelockReceiver, 2700000 * MULTIPLIER); // 2.7 mln tokens
  }


  //  –––––––––––––––––––––
  //  SETTERS
  //  –––––––––––––––––––––


  function unlock() public override {
    require(_locks[msg.sender] > 0, "unlock: No locked CODEXs!");

    uint256 amount = canUnlockAmount(msg.sender);

    _transfer(address(this), msg.sender, amount);
    _locks[msg.sender] = _locks[msg.sender].sub(amount);
    _lastUnlockBlock[msg.sender] = block.number;
    _totalLock = _totalLock.sub(amount);
  }

  function transferAll(address _to) public {
    _locks[_to] = _locks[_to].add(_locks[msg.sender]);

    if (_lastUnlockBlock[_to] < startReleaseBlock) {
      _lastUnlockBlock[_to] = startReleaseBlock;
    }

    if (_lastUnlockBlock[_to] < _lastUnlockBlock[msg.sender]) {
      _lastUnlockBlock[_to] = _lastUnlockBlock[msg.sender];
    }

    _locks[msg.sender] = 0;
    _lastUnlockBlock[msg.sender] = 0;

    _transfer(msg.sender, _to, balanceOf(msg.sender));
  }


  //  –––––––––––––––––––––
  //  SETTERS (ONLY OWNER)
  //  –––––––––––––––––––––


  function setReleaseBlock(uint256 _startReleaseBlock, uint256 _endReleaseBlock) public onlyOwner {
    require(_endReleaseBlock > _startReleaseBlock, "endReleaseBlock < startReleaseBlock");

    startReleaseBlock = _startReleaseBlock;
    endReleaseBlock = _endReleaseBlock;
  }

  function mint(address _to, uint256 _amount) public override onlyOwner {
    require(totalSupply().add(_amount) <= cap(), "mint: cap exceeded");

    _mint(_to, _amount);
    _moveDelegates(address(0), _delegates[_to], _amount);
  }

  function burn(address _account, uint256 _amount) public override onlyOwner {
    _burn(_account, _amount);
  }

  function lock(address _account, uint256 _amount) public override onlyOwner {
    require(_account != address(0), "no lock to address(0)");
    require(_amount <= balanceOf(_account), "no lock over balance");

    _transfer(_account, address(this), _amount);

    _locks[_account] = _locks[_account].add(_amount);
    _totalLock = _totalLock.add(_amount);

    if (_lastUnlockBlock[_account] < startReleaseBlock) {
      _lastUnlockBlock[_account] = startReleaseBlock;
    }

    emit Lock(_account, _amount);
  }

  function transferRights(address newOwner) public override onlyOwner {
    transferOwnership(newOwner);
  }


  //  –––––––––––––––––––––
  //  GETTERS
  //  –––––––––––––––––––––


  function totalBalanceOf(address _account) public override view returns (uint256) {
    return _locks[_account].add(balanceOf(_account));
  }

  function lockOf(address _account) public override view returns (uint256) {
    return _locks[_account];
  }

  function lastUnlockBlock(address _account) public override view returns (uint256) {
    return _lastUnlockBlock[_account];
  }

  function canUnlockAmount(address _account) public override view returns (uint256) {
    if (block.number < startReleaseBlock) {
      // When block number less than startReleaseBlock, no CODEXs can be unlocked
      return 0;
    } else if (block.number >= endReleaseBlock) {
      // When block number more than endReleaseBlock, all locked CODEXs can be unlocked
      return _locks[_account];
    } else {
      // When block number is more than startReleaseBlock but less than endReleaseBlock,
      // some CODEXs can be released
      uint256 releasedBlock = block.number.sub(_lastUnlockBlock[_account]);
      uint256 blockLeft = endReleaseBlock.sub(_lastUnlockBlock[_account]);
      return _locks[_account].mul(releasedBlock).div(blockLeft);
    }
  }

  function cap() public override view returns (uint256) {
    return _cap;
  }

  function unlockedSupply() public override view returns (uint256) {
    return totalSupply().sub(totalLock());
  }

  function totalLock() public override view returns (uint256) {
    return _totalLock;
  }


  //  –––––––––––––––––––––
  //  GOVERNANCE
  //
  //  Copied and modified from YAM code:
  //  https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
  //  https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
  //  Which is copied and modified from COMPOUND:
  //  https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol
  //
  // –––––––––––––––––––––


  /// @notice A record of each accounts delegate
  mapping(address => address) internal _delegates;

  /// @notice A checkpoint for marking number of votes from a given block
  struct Checkpoint {
    uint32 fromBlock;
    uint256 votes;
  }

  /// @notice A record of votes checkpoints for each account, by index
  mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

  /// @notice The number of checkpoints for each account
  mapping(address => uint32) public numCheckpoints;

  /// @notice The EIP-712 typehash for the contract's domain
  bytes32 public constant DOMAIN_TYPEHASH = keccak256(
    "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
  );

  /// @notice The EIP-712 typehash for the delegation struct used by the contract
  bytes32 public constant DELEGATION_TYPEHASH = keccak256(
    "Delegation(address delegatee,uint256 nonce,uint256 expiry)"
  );

  /// @notice A record of states for signing / validating signatures
  mapping(address => uint256) public nonces;

  /// @notice An event thats emitted when an account changes its delegate
  event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

  /// @notice An event thats emitted when a delegate account's vote balance changes
  event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);

  /**
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegator The address to get delegatee for
    */
  function delegates(address delegator) external view returns (address) {
    return _delegates[delegator];
  }

  /**
    * @notice Delegate votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
  function delegate(address delegatee) external {
    return _delegate(msg.sender, delegatee);
  }

  /**
    * @notice Delegates votes from signatory to `delegatee`
    * @param delegatee The address to delegate votes to
    * @param nonce The contract state required to match the signature
    * @param expiry The time at which to expire the signature
    * @param v The recovery byte of the signature
    * @param r Half of the ECDSA signature pair
    * @param s Half of the ECDSA signature pair
    */
  function delegateBySig(
    address delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 domainSeparator = keccak256(
      abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this))
    );

    bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));

    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

    address signatory = ecrecover(digest, v, r, s);
    require(signatory != address(0), "CODEX::delegateBySig: invalid signature");
    require(nonce == nonces[signatory]++, "CODEX::delegateBySig: invalid nonce");
    require(now <= expiry, "CODEX::delegateBySig: signature expired");
    return _delegate(signatory, delegatee);
  }

  /**
    * @notice Gets the current votes balance for `account`
    * @param account The address to get votes balance
    * @return The number of current votes for `account`
    */
  function getCurrentVotes(address account) external view returns (uint256) {
    uint32 nCheckpoints = numCheckpoints[account];
    return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
  }

  /**
    * @notice Determine the prior number of votes for an account as of a block number
    * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
    * @param account The address of the account to check
    * @param blockNumber The block number to get the vote balance at
    * @return The number of votes the account had as of the given block
    */
  function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
    require(blockNumber < block.number, "CODEX::getPriorVotes: not yet determined");

    uint32 nCheckpoints = numCheckpoints[account];
    if (nCheckpoints == 0) {
      return 0;
    }

    // First check most recent balance
    if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
      return checkpoints[account][nCheckpoints - 1].votes;
    }

    // Next check implicit zero balance
    if (checkpoints[account][0].fromBlock > blockNumber) {
      return 0;
    }

    uint32 lower = 0;
    uint32 upper = nCheckpoints - 1;
    while (upper > lower) {
      uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
      Checkpoint memory cp = checkpoints[account][center];
      if (cp.fromBlock == blockNumber) {
        return cp.votes;
      } else if (cp.fromBlock < blockNumber) {
        lower = center;
      } else {
        upper = center - 1;
      }
    }
    return checkpoints[account][lower].votes;
  }

  function _delegate(address delegator, address delegatee) internal {
    address currentDelegate = _delegates[delegator];
    uint256 delegatorBalance = balanceOf(delegator); // balance of underlying CODEXs (not scaled);
    _delegates[delegator] = delegatee;

    emit DelegateChanged(delegator, currentDelegate, delegatee);

    _moveDelegates(currentDelegate, delegatee, delegatorBalance);
  }

  function _moveDelegates(
    address srcRep,
    address dstRep,
    uint256 amount
  ) internal {
    if (srcRep != dstRep && amount > 0) {
      if (srcRep != address(0)) {
        // decrease old representative
        uint32 srcRepNum = numCheckpoints[srcRep];
        uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
        uint256 srcRepNew = srcRepOld.sub(amount);
        _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
      }

      if (dstRep != address(0)) {
        // increase new representative
        uint32 dstRepNum = numCheckpoints[dstRep];
        uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
        uint256 dstRepNew = dstRepOld.add(amount);
        _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
      }
    }
  }

  function _writeCheckpoint(
    address delegatee,
    uint32 nCheckpoints,
    uint256 oldVotes,
    uint256 newVotes
  ) internal {
    uint32 blockNumber = safe32(block.number, "CODEX::_writeCheckpoint: block number exceeds 32 bits");

    if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
      checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
    } else {
      checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
      numCheckpoints[delegatee] = nCheckpoints + 1;
    }

    emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
  }

  function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
    require(n < 2**32, errorMessage);
    return uint32(n);
  }

  function getChainId() internal pure returns (uint256) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    return chainId;
  }
}