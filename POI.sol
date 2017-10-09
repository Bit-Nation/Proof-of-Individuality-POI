/*
 * Proof of Individuality (POI).
 * Author: Johan Nygren <emailsareobsolete@gmail.com>
 */
pragma solidity ^0.4.6;
contract ProofOfIndividuality {


  PseudonymRound public currentPOIs;

  address public currentRound;
  uint public groupSize;

  uint public commitment;
  uint public generateAddress;
  uint public pseudonymEvent;
  uint public issuePOIs;
  uint public antiAttackPeriod;
  uint public withdrawals;
  uint public roundLength;
  uint public previousRound;

  function ProofOfIndividuality() {
    groupSize = 5;
    roundLength = 24 hours;
    commitment = 11 hours;
    generateAddress = 22 hours;
    pseudonymEvent = 24 hours - 15 minutes;
    issuePOIs = 24 hours;
    antiAttackPeriod = 26 hours;
    withdrawals = 28 hours;
    currentRound = new PseudonymRound(
                          now,
                          groupSize, 
                          0,
                          commitment,
                          generateAddress,
                          pseudonymEvent,
                          issuePOIs,
                          withdrawals,
                          antiAttackPeriod,
                          0
                        );
    previousRound = now;  
  }

  function newRound(uint _newDepositSize) {
    if(msg.sender != currentRound) throw;
    address previousPOIround = currentPOIs;
    currentPOIs = PseudonymRound(currentRound);
    currentRound = new PseudonymRound(
                          previousRound + roundLength,
                          groupSize, 
                          _newDepositSize,
                          commitment,
                          generateAddress,
                          pseudonymEvent,
                          issuePOIs,
                          withdrawals,
                          antiAttackPeriod,
                          previousPOIround
                        );
    previousRound += roundLength;
  }

  function verifyPOI(address _nym) public returns (bool) {
    return currentPOIs.verifyPOI(_nym);
  }

  function dissolveCurrentPOIs() {
    if(msg.sender != address(currentPOIs)) throw;
    currentPOIs = PseudonymRound(0x0000000000000000000000000000000000000000);
  }

}

contract PseudonymRound {

  ProofOfIndividuality public proofOfIndividuality;
  PseudonymRound public previousPOIround; // previous POI holders can dissolve the current round, if 30% vote for it
                                          // this protects against large scale attacks where someone controls 3-5x total number of commitedUsers

  uint public numUsers;
  uint public groupSize;  
  uint public depositSize;

  mapping(address => uint256) public deposit;
  mapping(address => bytes32) public userHash;
  mapping(address => uint) public userGroup;
  
  mapping(uint => address[]) public pseudonymGroup;
  mapping(uint => bytes32) public partyAddress;
  
  uint public POIcount;
  mapping(address => bool) public POI;
  function verifyPOI(address _nym) public returns (bool) { return POI[_nym]; }  

  bytes32 entropy;
  

  // max value of a sha3 hash
  bytes32 maxHash = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    
  
  uint public registration;
  uint public commitment;
  uint public generateAddress;
  uint public pseudonymEvent;
  uint public issuePOIs;
  uint public antiAttackPeriod;
  uint public withdrawals;
  
  modifier atTime(uint _currentState, uint _nextState) {
    if(_nextState == 0) {
      if(now < _currentState) throw;
      _;
    }
    else {
      if (now < _currentState
      || now > _nextState) throw;   
      _; 
    }
  }
  
  function numGroups() public constant returns(uint){ 
      uint numberOfGroups = numUsers / groupSize;  
      if(numUsers%groupSize > 0) numberOfGroups++; 
      return numberOfGroups;
  }
  
  function PseudonymRound(uint _deployment, uint _groupSize, uint _newDepositSize, uint _commitment, uint _generateAddress, uint _pseudonymEvent, uint _issuePOIs, uint _withdrawals, uint _antiAttackPeriod, address _previousPOIround) {
    proofOfIndividuality = ProofOfIndividuality(msg.sender);
    registration = _deployment;
    groupSize = _groupSize;
    depositSize = _newDepositSize;
    commitment = _deployment + _commitment;
    generateAddress = _deployment + _generateAddress;
    pseudonymEvent = _deployment + _pseudonymEvent;
    issuePOIs = _deployment + _issuePOIs;
    withdrawals = _deployment + _withdrawals;
    antiAttackPeriod = _deployment + _antiAttackPeriod;
    entropy = sha3(block.blockhash(block.number));
    previousPOIround = PseudonymRound(_previousPOIround);
  }

  function register() payable atTime(registration, commitment) {
    if(userHash[msg.sender] != bytes32(0)) throw; // already registered
    if(msg.value < depositSize) throw;
    // generate a hash for the given user, using previous entropy, 
    // senders address and current blocknumber.
    bytes32 h = sha3(entropy, msg.sender, block.blockhash(block.number));
    entropy = h;
    userHash[msg.sender] = h;
    numUsers++;
    deposit[msg.sender] += msg.value;
    depositSizeVote[msg.sender] += msg.value;
  }
  
  function commit() atTime(commitment, pseudonymEvent) {
    if(userHash[msg.sender] == bytes32(0)) // not registered
    if(userGroup[msg.sender] != 0) throw; // group already assigned
  
    uint groupNumber = uint(userHash[msg.sender]) / (uint(maxHash) / numGroups()) + 1;
    
    if(pseudonymGroup[groupNumber].length >= groupSize) {
        for(uint i = 0; i < numGroups(); i++) {
            if(groupNumber - i >= 1) {
                if(pseudonymGroup[groupNumber - i].length < groupSize) { groupNumber -= i; break; }
            }
            if(groupNumber + i <= numGroups()) {
                if(pseudonymGroup[groupNumber + i].length < groupSize) { groupNumber += i; break; }
            }
        }
    }
    userGroup[msg.sender] = groupNumber;
    pseudonymGroup[groupNumber].push(msg.sender);

    Nym[msg.sender].positiveNYM = 5000;
    Nym[msg.sender].negativeNYM = 1500;
  }
  
  function generatePseudonymPartyAddress() atTime(generateAddress, 0) {
    uint groupNumber = userGroup[msg.sender];
    if(groupNumber == 0) throw; // not in a pseudonymGroup
    if(partyAddress[groupNumber] != bytes32(0)) throw;
    partyAddress[groupNumber] = sha3(pseudonymGroup[groupNumber]);
  }
  
  function getPseudonymAddress() atTime(generateAddress, 0) returns (bytes32) {
    uint groupNumber = userGroup[msg.sender];
    if(partyAddress[groupNumber] == 0) generatePseudonymPartyAddress();
    return partyAddress[groupNumber];
  }
  
  struct NYM {
    int positiveNYM;
    int negativeNYM;
  }
  
  mapping(address => NYM) public Nym;
  
  mapping(address => int) public points;
  
  modifier inParty(address _to) {
    if(userGroup[_to] != userGroup[msg.sender]) throw;
    _;
  }
  
  /* Each pseudonym can give out +5000 NYM. A pseudonyms points can not go above 6000 */
  
  function givePositiveNYM(address _to, int _nym) atTime(pseudonymEvent, issuePOIs) inParty(_to) {
    if(_to == msg.sender) throw;
    if(_nym > Nym[msg.sender].positiveNYM) _nym = Nym[msg.sender].positiveNYM;
    if(points[_to] + _nym > 6000) _nym = 6000 - points[_to];
    points[_to] += _nym;
    Nym[msg.sender].positiveNYM -= _nym;
  }
  
  /* Each pseudonym can give out -1500 NYM. A pseudonyms points can not go below 0 */
  
  function giveNegativeNYM(address _to, int _nym) atTime(pseudonymEvent, issuePOIs) inParty(_to) {
    if(_to == msg.sender) throw;
    if(_nym > Nym[msg.sender].negativeNYM) _nym = Nym[msg.sender].negativeNYM;
    if(points[_to] - _nym < 0) _nym = points[_to];
    points[_to] -= _nym;
    Nym[msg.sender].negativeNYM -= _nym;
  }
  
  /* Each pseudonym needs 4000 points to be verified */

  mapping(uint => bool) groupProcessed;

  function submitVerifiedUsers() atTime(issuePOIs, 0) {
      uint groupNumber = userGroup[msg.sender];
      if(groupProcessed[groupNumber] == true) throw;
      for(uint i = 0; i < pseudonymGroup[groupNumber].length; i++){
          address nym = pseudonymGroup[groupNumber][i];
          if(points[nym] >= 4000) POI[nym] = true;
          else setDepositPenalty(nym);
      }
      groupProcessed[groupNumber] = true;
  }
  
  uint public depositGovernance;
  uint depositPenalties;
  mapping(address => uint) depositPenalty;
  
  mapping(address => uint) withdrawnShareOfPenalty;
  
  mapping(address => uint) public depositSizeVote;
  
  function vote(uint _depositSize) payable atTime(registration, pseudonymEvent) {
    if(depositSizeVote[msg.sender] + msg.value < _depositSize) _depositSize = depositSizeVote[msg.sender] + msg.value;
    depositGovernance -= depositSizeVote[msg.sender];
    depositGovernance += _depositSize;
    depositSizeVote[msg.sender] = _depositSize;
    deposit[msg.sender] += msg.value;
  }
  
  function countVotes() atTime(pseudonymEvent, 0) {
    uint newDepositSize;
    if(numUsers != 0) newDepositSize = depositGovernance / numUsers;
    proofOfIndividuality.newRound(newDepositSize);
  }
  
  
  function setDepositPenalty(address _nym) internal {
    depositPenalty[_nym] = depositSize;
    depositPenalties += depositSize;
  }

  function getFromDepositPenalty() atTime(withdrawals, 0) {
    if(verifyPOI(msg.sender) != true) throw;
    if(depositPenalties == 0) throw;
    uint previousPOIcount = previousPOIround.POIcount();
    uint shareOfPenalty = depositPenalties / previousPOIcount;
    if(shareOfPenalty > withdrawnShareOfPenalty[msg.sender]) {
      uint shareToWithdraw = shareOfPenalty - withdrawnShareOfPenalty[msg.sender];
      withdrawnShareOfPenalty[msg.sender] += shareToWithdraw;
      deposit[msg.sender] += shareToWithdraw;
    }
  }

  function withdrawDeposit() atTime(withdrawals, 0) {
    if(deposit[msg.sender] == 0) throw;
    if(dissolvePenalty != 0) {
        deposit[msg.sender] -= dissolvePenalty;
        depositPenalty[msg.sender] = 0;
    }
    deposit[msg.sender] -= depositPenalty[msg.sender];
    uint d = deposit[msg.sender];
    deposit[msg.sender] = 0;

    if(!msg.sender.send(d)) throw;
  }

  mapping(address => bool) public voteToDissolve;
  uint public totalVotesToDissolve;

  function myGroupWasAttackedVoteToDissolveThisRound() atTime(pseudonymEvent, 0) {
    if(voteToDissolve[msg.sender] == true) throw;
    if(previousPOIround.verifyPOI(msg.sender) == false) throw;
    totalVotesToDissolve++;
    voteToDissolve[msg.sender] = true;
  }
  mapping(address => bool) public hasWithdrawn;

  function withdrawDissolvePenalty() atTime(withdrawals, 0) {
    if(dissolvePenalty == 0) throw;
    if(previousPOIround.verifyPOI(msg.sender) == false) throw;
    if(hasWithdrawn[msg.sender] == true) throw;
    uint previousPOIcount = previousPOIround.POIcount();
    uint amountToWithdraw = dissolvePenalty * numUsers / previousPOIcount;
    hasWithdrawn[msg.sender] = true;
    if(!msg.sender.send(amountToWithdraw)) throw;
  }

  uint dissolvePenalty;
  
  function executeDissolve() atTime(antiAttackPeriod, 0) {
    uint previousPOIcount = previousPOIround.POIcount();
    if(previousPOIcount * 100 / totalVotesToDissolve < 30) throw; // 30% threshold
    depositPenalties = 0; // reset deposit penalites
    dissolvePenalty = depositSize * 30 / 100;
    proofOfIndividuality.dissolveCurrentPOIs();
  }

}
