// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;
import "./GovToken.sol";


contract RentalSC {
    
    string public name; // name of the contract
    mapping (uint256 => Rental) private rental; // a mapping from rental id to rental
    mapping (uint256 => Dispute) private dispute; // a mapping from rental id to dispute
    GovToken govTokenSC;
    
    uint256 MEDIATOR_NO = 5; // number of mediators to decided a dispute
    uint256 RESPONSE_TIME = 14 * 1 days;  // days
    uint256 TOKEN_REWARD = 100; // amount of tokens a mediator gets for mediating 
    uint256 MEDIATOR_MIN_TOKEN = 10000; // amount of tokens a mediator needs to hold 
    
    // dummy variable for implementing random choice of mediators
    uint256 mediator_choice;
    
    // rental state 
    enum State {
        Created, // 0  Rental has benn created
        Signed, // 1  Rental has been signed
        DepositPaid, // 2 Deposit and fee has been payed by the tenant
        Confirmed, // 3 The tenant has confirmed the rental
        Canceled, // 4 The tenant has canceled the rental
        Terminated, // 5 The tenant/landlord has terminated the rental
        Offer, // 6 The landlord has made an offer for the deposit
        DisputeOpened, // 7 The tenant has opened a dispute
        DisputePaid, // 8 The landlord has paid the dispute fee
        Agreement, // 9 The landlord and tenant have agreed on the deposit 
        Claimed // 10 The landlord and tenant have claimed the deposit
    }
    
    // different roles
    enum Role {
        Landlord, // 0 
        Tenant, // 1 
        Mediator // 2
    }
    
    // defining rental struct
    struct Rental {
        uint256 ID; // the rental identifier 
        address landlordID; 
        address tenantID; 
        
        uint256 depositAmount;
        string[] moveInPictures;
        string[] moveOutPictures;
        
        State rentalState;
        
        uint256 terminationTimestamp;
        uint256 landlordOffer; // offer of the deposit amount the tenant should get back
        bool tenantClaimed;
        bool landlordClaimed;
        
        uint256 serviceFee;
        uint256 disputeFee;
        uint256 rewardAmount;
        
    } 
    
    struct MediatorVote{
        bool isValid;
        bool voted;
    }
    
    struct Dispute {
        uint256 ID; // rental id 
        mapping (address => MediatorVote) mediatorVotes; // the ruling of the mediators
        address[] meds; // used to view assigned mediators 

        uint256 tenantOffer;
        uint256 landlordOffer;
        
        uint256 votedCount;
        uint256 tenantVotes;
        uint256 landlordVotes;
        
        uint256 decision; // 0 = not decided, 1 for tenant, 2 for landlord

    }
    
    struct Mediator {
        address ID;
        Role role;
        string name;
        bool isDefined;
    }
    
    struct Actor {
        Role role;
        string name;
        bool isDefined;
    }
    

    Mediator[] private mediators;
    mapping(address => bool) knownMediators;
    mapping (address => Actor) private actors;

    // constructor, to be intialized when the contract is deployed 
    constructor (string memory _name, address _govTokenSC) {
        name = _name;
        mediator_choice = 0;
        govTokenSC = GovToken(_govTokenSC);
    }

    
    function createInitalOffer(uint256 _id, uint256 _offerAmount, string[] memory _moveOutPictures) public OnlyLandlord {
        require(rental[_id].rentalState == State.Terminated, "rental has not been terminated");
        require(_offerAmount <= rental[_id].depositAmount &&  _offerAmount >= 0, "offer not in range");
        require(rental[_id].landlordID == msg.sender, "caller is not tenant of contract");
        
        rental[_id].landlordOffer = _offerAmount;
        rental[_id].moveOutPictures = _moveOutPictures;
        rental[_id].rentalState = State.Offer;
    }
    
    function createNewOffer(uint256 _id, uint256 _offerAmount) public OnlyLandlord {
        require(rental[_id].rentalState == State.Offer, "rental not in state: offer");
        require(_offerAmount <= rental[_id].depositAmount &&  _offerAmount >= 0, "offer not in range");
        require(rental[_id].landlordID == msg.sender, "caller is not tenant of contract");
        
        rental[_id].landlordOffer = _offerAmount;
    }
    
    function acceptOffer(uint256 _id) public OnlyTenant {
        require(rental[_id].rentalState == State.Offer, "no affer has been made");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");

        rental[_id].rentalState = State.Agreement;
    }
    

   function newRental(uint256 _id, uint256 _depositAmount, address _tenantID) public OnlyLandlord {
        Rental storage newrental = rental[_id];
        newrental.ID = _id;
        newrental.landlordID = msg.sender;
        newrental.tenantID = _tenantID;
        newrental.depositAmount = _depositAmount;
        newrental.rentalState = State.Created;
        newrental.landlordOffer = 0;
        newrental.tenantClaimed = false;
        newrental.landlordClaimed = false;
        newrental.disputeFee = (_depositAmount/100)*2;
        newrental.rewardAmount = newrental.disputeFee / MEDIATOR_NO;
        newrental.serviceFee = _depositAmount / 2;
    }
    
    function payDepositServiceFee(uint256 _id) payable public OnlyTenant returns (bool success) { 
        require(rental[_id].depositAmount + rental[_id].serviceFee == msg.value, "amount not euqal to deposit");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");

        rental[_id].rentalState = State.DepositPaid;
        return true;
    }

    function confirmRental(uint256 _id, string[] memory _moveInPictures) public OnlyTenant { 
        require(rental[_id].rentalState == State.DepositPaid, "deposit has not been paid");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");
        rental[_id].moveInPictures = _moveInPictures;
        rental[_id].rentalState = State.Confirmed;
        
        // transfer service fee to landlord
        payable(rental[_id].landlordID).transfer(rental[_id].serviceFee);
    }

    function cancelRental(uint256 _id) public OnlyTenant { 
        require(rental[_id].rentalState == State.DepositPaid, "deposit has not been paid");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");
        rental[_id].rentalState = State.Claimed;

        // refund deposit and deposit fee
        refund(msg.sender, rental[_id].depositAmount + rental[_id].serviceFee);
    }
    
    function refund(address recipient, uint256 amount) private {
		payable(recipient).transfer(amount);
    } 


    function terminateRental(uint256 _id) public OnlyTenantLandlord { 
        require(rental[_id].tenantID == msg.sender || (rental[_id].landlordID == msg.sender) , "caller is not tenant or landlord of contract");
        rental[_id].terminationTimestamp = block.timestamp;
        rental[_id].rentalState = State.Terminated;
    }
    
        
    function claimDepositNoRespTerminated(uint256 _id) public OnlyTenant {
        require(rental[_id].rentalState == State.Terminated , "rental has not been terminated");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");
        require(rental[_id].terminationTimestamp + RESPONSE_TIME  >= block.timestamp, "deadline for reponse not met");

        rental[_id].rentalState = State.Claimed;

        // refund
        refund(msg.sender, rental[_id].depositAmount);
    }
    
            
    function claimDepositNoRespDispute(uint256 _id) public OnlyTenant {
        require(rental[_id].rentalState == State.DisputeOpened , "rental not in state: Dispute Opened");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");
        require(rental[_id].terminationTimestamp + RESPONSE_TIME  >= block.timestamp, "deadline for reponse not met");

        rental[_id].rentalState = State.Claimed;

        // refund
        refund(msg.sender, rental[_id].depositAmount + rental[_id].serviceFee);
    }
    
    
    function claimDepositTenant(uint256 _id) public OnlyTenant {
        require(rental[_id].rentalState == State.Agreement, "agreement has not been reached");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");
        require(rental[_id].tenantClaimed == false, "deposit already reveiced");

        if (rental[_id].landlordClaimed){
            rental[_id].rentalState = State.Claimed;
        }

        rental[_id].tenantClaimed = true;
        
        // refund
        refund(msg.sender, rental[_id].landlordOffer);
    }
    
    function claimDepositLandlord(uint256 _id) public OnlyLandlord {
        require(rental[_id].rentalState == State.Agreement, "agreement has not been reached");
        require(rental[_id].landlordID == msg.sender, "caller is not landlord of contract");
        require(rental[_id].landlordClaimed == false, "deposit already reveiced");


        if (rental[_id].tenantClaimed){
            rental[_id].rentalState = State.Claimed;
        }

        rental[_id].landlordClaimed = true;
        
        // refund
        refund(msg.sender, rental[_id].depositAmount - rental[_id].landlordOffer);
    }
    
    function vote(uint256 _id, bool forTenant) public { 
        require(rental[_id].rentalState == State.DisputePaid, "no dispute started");
        
        // check weather mediator is allowed to vote 
        if (dispute[_id].mediatorVotes[msg.sender].isValid == false) {
           revert("can only be called by assigned mediator");
        }
        
        // check weather mediator has already voted
        if (dispute[_id].mediatorVotes[msg.sender].voted == true) {
           revert("mediator already voted");
        }
        
        if (forTenant) {
            dispute[_id].tenantVotes = dispute[_id].tenantVotes + 1;
        } else {
            dispute[_id].landlordVotes = dispute[_id].landlordVotes + 1;
        }
        
        dispute[_id].mediatorVotes[msg.sender].voted = true;
        
        // reward mediator with gov tokens and crypto
        govTokenSC.mintTo(msg.sender, TOKEN_REWARD);
        payable(msg.sender).transfer(rental[_id].rewardAmount);

        
        // check if all voted and set to resolve
        dispute[_id].votedCount = dispute[_id].votedCount+1;
        
        if (dispute[_id].votedCount == MEDIATOR_NO) {
            // if landlord wins
            dispute[_id].decision = 2;
            rental[_id].landlordOffer = dispute[_id].landlordOffer;
            
            // if tenant wins
            if (dispute[_id].tenantVotes > dispute[_id].landlordVotes) {
                dispute[_id].decision = 1;
                rental[_id].landlordOffer = dispute[_id].tenantOffer;
            }
            
            rental[_id].rentalState = State.Agreement;
        }
    }
    
    
    function openDispute(uint256 _id, uint256 _offerAmount) payable public OnlyTenant returns (bool success) {
        require(rental[_id].rentalState == State.Offer, "no offer has been made");
        require(mediators.length >= MEDIATOR_NO, "not enough mediators in the system");
        require(rental[_id].tenantID == msg.sender, "caller is not tenant of contract");
        require(_offerAmount <= rental[_id].depositAmount &&  _offerAmount >= 0, "offer not in range");
        require(rental[_id].disputeFee == msg.value, "sent wrong amount dispute fee");


        Dispute storage newdisptue = dispute[_id];
        newdisptue.ID = _id;
        newdisptue.tenantOffer = _offerAmount;
        newdisptue.landlordOffer =  rental[_id].landlordOffer;
        newdisptue.votedCount = 0;
        newdisptue.decision = 0;

        // choose mediators 
        while (dispute[_id].meds.length != MEDIATOR_NO) {
            uint256 rand = getRand(mediators.length);
            if (valueExists(dispute[_id].meds, mediators[rand].ID) == false && 
                    // check that mediator has enoguh tokens to qualify for mediation
                    govTokenSC.balanceOf(mediators[rand].ID) >= MEDIATOR_MIN_TOKEN){
                        
                dispute[_id].mediatorVotes[mediators[rand].ID].isValid = true;
                dispute[_id].mediatorVotes[mediators[rand].ID].voted = false;
                dispute[_id].meds.push(mediators[rand].ID);
            }
        }

        rental[_id].terminationTimestamp = block.timestamp;
        rental[_id].rentalState = State.DisputeOpened;
        
        return true;
    }
    
    
    function payDisputeFee(uint256 _id) payable public OnlyLandlord returns (bool success) { 
        require(rental[_id].rentalState == State.DisputeOpened, "no offer has been made");
        require(rental[_id].landlordID == msg.sender, "caller is not landlord of contract");
        require(rental[_id].disputeFee == msg.value, "sent wrong amount dispute fee");
        
        rental[_id].rentalState = State.DisputePaid;
        return true;
    }
    

    function valueExists(address[] memory arr, address val) pure private returns (bool exists_){
        bool exists = false;
        for (uint i = 0; i<arr.length; i++) {
            if(arr[i] == val){
                exists = true;
            }
        }
        return exists;
    }
    
    // dummy function for getting random number
    function getRand(uint256 range) private returns (uint256 randomNumber){
        uint256 rand = mediator_choice % range;
        mediator_choice = mediator_choice + 1;
        return rand;
    }
    
    modifier OnlyLandlord() {
        require(actors[msg.sender].role == Role.Landlord && actors[msg.sender].isDefined ,'caller is not a landlord');
        _;
    }
    
    modifier OnlyTenant() {
        require(actors[msg.sender].role == Role.Tenant && actors[msg.sender].isDefined, 'caller is not a tenant');
        _;
    }
    
    modifier OnlyTenantLandlord() {
        require(actors[msg.sender].role == Role.Tenant && actors[msg.sender].isDefined
        || actors[msg.sender].role == Role.Landlord && actors[msg.sender].isDefined, 'caller is not a tenant or landlord');
        _;
    }
    
    
    function register(Role _role, string memory _name) public {
        Actor memory actor = actors[msg.sender];
        actor.role = _role;
        actor.name = _name;
        actor.isDefined = true;
        actors[msg.sender] = actor;
    }
    
    function registerMediator(string memory _name) public {

        if(knownMediators[msg.sender]) revert("already mediator");
        
        Mediator memory mediator;
        mediator.ID = msg.sender;
        mediator.role = Role.Mediator;
        mediator.name = _name;
        mediator.isDefined = true;
        knownMediators[msg.sender] = true;
        mediators.push(mediator);
    }
    
    
    function getDisputeInfo(uint256 _id) public view returns 
    (
        uint256 contract_id,
        address[] memory meds_, 

        uint256 tenant_offer,
        uint256 landlord_offer,
        
        uint256 voted_count,
        uint256 tenant_votes,
        uint256 landlord_votes,
        
        uint256 decision_
    ){
        contract_id = dispute[_id].ID;  
        
        meds_ = dispute[_id].meds; 
        tenant_offer = dispute[_id].tenantOffer; 
        landlord_offer = dispute[_id].landlordOffer; 
        voted_count = dispute[_id].votedCount; 
        tenant_votes = dispute[_id].tenantVotes; 
        landlord_votes= dispute[_id].landlordVotes; 
        decision_ = dispute[_id].decision; 
         
    }
    
    
    function getRentalInfo(uint256 _id) public view returns 
    (
        uint256 contract_id, 
        address landlord_id, 
        address tenant_id, 
        uint256 deposit_amount, 
        State current_state,
        uint256 termination_timestamp,
        uint256 landlord_offer,
        bool tenant_claimed,
        bool landlord_claimed,
        uint256 dispute_fee,
        uint256 reward_amount
    )
    
    {
        contract_id = rental[_id].ID; 
        landlord_id = rental[_id].landlordID;
        tenant_id = rental[_id].tenantID;
        deposit_amount = rental[_id].depositAmount;
        current_state = rental[_id].rentalState;
        termination_timestamp = rental[_id].terminationTimestamp;
        landlord_offer = rental[_id].landlordOffer;
        tenant_claimed = rental[_id].tenantClaimed;
        landlord_claimed = rental[_id].landlordClaimed;
        dispute_fee = rental[_id].disputeFee;
        reward_amount = rental[_id].rewardAmount;
    }

    // retrieve an actor information
    function getActorInfo(address _addr) public view returns
    (
        Role _role,
        string memory _name
    )
    {
        _role = actors[_addr].role;
        _name = actors[_addr].name;
    }   

}