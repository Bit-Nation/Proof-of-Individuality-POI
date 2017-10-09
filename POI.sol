pragma solidity ^0.4.6;
contract ProofOfIndividuality {

  PseudonymRound public currentPOIs;
  address public currentRound;
  uint public groupSize;

  uint public commitment;
  uint public generateAddress;
  uint public pseudonymEvent;
  uint public issuePOIs;
  uint public roundLength;
  uint public previousRound;

  function ProofOfIndividuality() {
    groupSize = 5;
    roundLength = 28 days;
    commitment = 14 days;
    generateAddress = 26 days;
    pseudonymEvent = 28 days - 15 minutes;
    issuePOIs = 28 days;
    currentRound = new PseudonymRound(
                          now,
                          groupSize, 
                          0,
                          commitment,
                          generateAddress,
                          pseudonymEvent,
                          issuePOIs
                        );
    previousRound = now;  
  }

  function newRound(uint _newDepositSize) {
    if(msg.sender != currentRound) throw;
    currentPOIs = PseudonymRound(currentRound);
    currentRound = new PseudonymRound(
                          previousRound + roundLength,
                          groupSize, 
                          _newDepositSize,
                          commitment,
                          generateAddress,
                          pseudonymEvent,
                          issuePOIs
                        );
    previousRound += roundLength;
  }

  function verifyPOI(address _nym) public returns (bool) {
    return currentPOIs.verifyPOI(_nym);
  }

}

contract PseudonymRound {

  ProofOfIndividuality public proofOfIndividuality;

  uint public numUsers;
  uint public groupSize;  
  uint public depositSize;

  uint public commitedUsers;
  mapping(address => uint256) public deposit;
  mapping(address => bytes32) public userHash;
  mapping(address => uint) public userGroup;
  
  mapping(uint => address[]) public pseudonymGroup;
  mapping(uint => bytes32) public partyAddress;
  
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
  
  function PseudonymRound(uint _deployment, uint _groupSize, uint _newDepositSize, uint _commitment, uint _generateAddress, uint _pseudonymEvent, uint _issuePOIs) {
    proofOfIndividuality = ProofOfIndividuality(msg.sender);
    registration = _deployment;
    groupSize = _groupSize;
    depositSize = _newDepositSize;
    commitment = _deployment + _commitment;
    generateAddress = _deployment + _generateAddress;
    pseudonymEvent = _deployment + _pseudonymEvent;
    issuePOIs = _deployment + _issuePOIs;
    entropy = sha3(block.blockhash(block.number));
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

    commitedUsers++;
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
          else depositPenalty(nym);
      }
      groupProcessed[groupNumber] = true;
  }
  
  uint public depositGovernance;
  uint depositPenalties;

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
  
  function depositPenalty(address _nym) internal {
    deposit[_nym] -= depositSize;
    depositPenalties += depositSize;
  }

  function getFromDepositPenalty() atTime(issuePOIs, 0) {
    if(verifyPOI(msg.sender) != true) throw;
    uint shareOfPenalty = depositPenalties / commitedUsers;
    if(shareOfPenalty > withdrawnShareOfPenalty[msg.sender]) {
      uint shareToWithdraw = shareOfPenalty - withdrawnShareOfPenalty[msg.sender];
      withdrawnShareOfPenalty[msg.sender] += shareToWithdraw;
      deposit[msg.sender] += shareToWithdraw;
    }
  }

  function withdrawDeposit() atTime(issuePOIs, 0) {
    if(deposit[msg.sender] == 0) throw;
    uint d = deposit[msg.sender];
    deposit[msg.sender] = 0;
    if(!msg.sender.send(d)) throw;
  }

}
