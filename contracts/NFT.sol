// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract CommunityOrb is ERC721Enumerable, ERC721Burnable, Ownable{

    using Counters for Counters.Counter;

    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Factory contract.
    address public immutable factory;

    /// @notice The address where fees will be sent.
    address public orbofiVault;
    

    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    
    /// @notice Fee taken on each mint
    /// @dev Set to comprise 5% of pricePerUnit on every mint
    uint8 public constant feeDenominator = 20;

    /// @notice The max percent a creator can set.
    uint8 public constant CREATOR_PERCENT_MAX = 69;

    
    /*//////////////////////////////////////////////////////////////
                             BOOLEANS
    //////////////////////////////////////////////////////////////*/
    /// @notice Checks if users can start claiming their shares.
    bool public isClaimable = false;

    /// @notice Checks if user has already withdraw.
    bool private hasWithdraw = false;


    /*//////////////////////////////////////////////////////////////
                             NFT DATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Price of NFT. 
    string public orbName;

    /// @notice Price of NFT. 
    uint256 public pricePerUnit;

    /// @notice Maximum amount of NFTs.
    uint256 public maxSupply;

    /// @notice Amount to be given for free from the maxSupply.
    uint256 public giveawaySupply;

    /// @notice token URI
    string private _URI;

    /// @notice  Percent that the creator gets to keep after sale.
    /// the rest goes to the holders.
    uint8 public creatorPercent;

     
    struct UserInfo {
        /// @notice amount that the user has claimed
        uint256 amount;

        /// @notice time when the user has claimed the revenue share
        uint256 timestamp;

        /// @notice indicates if a user has claimed or not
        bool status;

    }

    mapping(uint256 => UserInfo) public userInfo;

     /// @notice indicates if a user has claimed the giveaway
    mapping(address => bool) public hasClaimedGiveAway;
    
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event WithDrawn(address indexed owner, uint256 amount);

    event UpdatedURI(string oldURI, string newURI);

    event UpdatedGiveAwayStatus(bool status);

    event FeeUpdated(uint8 creatorPercent);

    Counters.Counter private _tokenIdCounter;

      


    modifier claimActive() {
        require(isClaimable, "Claiming has not yet started");
        _;
    }

    modifier isCorrectPayment(uint256 price) {
        require(price  == msg.value, "Incorrect ETH value sent"
        );
        _;
    }

    modifier canMint {
        require(_tokenIdCounter.current() < maxSupply, "Supply is unavailable");
        _;
    }
    modifier canMintGiveAway {
        require(giveawaySupply > 0, "Supply is unavailable"
        );
        _;
    }

    modifier realNFTOwner(address _user, uint256 _tokenId) {
        require(ownerOf(_tokenId) == _user, "Not the owner of the NFT");
        _;
    }

    modifier hasClaimShares(uint256 _tokenId) {
        require(!userInfo[_tokenId].status, "Already claimed");
        _;
    }

    modifier hasClaimGiveAway(address _user) {
        require(!hasClaimedGiveAway[_user], "Already claimed");
        _;
    }
  
    constructor( string memory name, string memory symbol) ERC721(name, symbol) {
        factory = msg.sender;  
    }



    /*//////////////////////////////////////////////////////////////
                                MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints a free NFT from the maxSupply
    function mintGiveAway(address to) external  
        canMintGiveAway
        hasClaimGiveAway(to)
    {

        hasClaimedGiveAway[to] = true;
        giveawaySupply -= 1;
        _autoMint(to);
    }
    

    function mint(address to) external 
     payable  
     canMint
     isCorrectPayment(pricePerUnit)
      {
        
        // TODO: make sure that the eth already exists within the contract

        uint256 orb_fee =  pricePerUnit / feeDenominator; 
        
        (bool success, ) = orbofiVault.call{value: orb_fee}("");
        require(success, "FAILED TO SEND FEE");

        _autoMint(to);
    }

     function _autoMint(address to) internal {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                                CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    function setClaimable(bool status) external onlyOwner {
        isClaimable = status;
    }


    /// @notice Returns the amount a user is supposed to claim depending on the amount of nft's owned
    function calculateAllocation(address _address) public view returns (uint256)  {
        if (balanceOf(_address) == 0) return 0;

      
        uint256 earned_percent =  balanceOf(_address) * 100 / totalSupply(); 
        
        // TODO  the amount to be distributed (address(this).balance)
        // should be constant, so create a global variable
        // that will store the remaining balance after the owner withdraw
        return earned_percent * address(this).balance; 
        
    }

    function claim(address to, uint256 tokenId) external
        claimActive
        realNFTOwner(to, tokenId)
        hasClaimShares(tokenId)

     {
       require(hasWithdraw, "Owner must withdraw first");

        uint256 amount = calculateAllocation(to);
        userInfo[tokenId].status = true;
        userInfo[tokenId].amount = amount;
        userInfo[tokenId].timestamp = block.timestamp;
        
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "FAILED TO SEND ETH");

    }


     /*//////////////////////////////////////////////////////////////
                    WITHDRAW LOGIC                 
    //////////////////////////////////////////////////////////////*/
    function withdraw(address to) external 
        onlyOwner 
         {

        hasWithdraw = true;
        uint256 creator_fee = creatorPercent * address(this).balance / 100;
        require(creator_fee > 0 ,  " NOTHING TO WITHDRAW");

        (bool sent, ) = to.call{value: creator_fee}("");
        require(sent, " FAILED TO SEND ETH");

        emit WithDrawn(msg.sender, creator_fee);

        // amount_to_distributed = address(this).balance
        // this will lead to some errors if the
        // owner will call the withdraw twice


    }

    // add logic to withdraw erc-20

    /*//////////////////////////////////////////////////////////////
                                CREATOR CONTROLS
    //////////////////////////////////////////////////////////////*/

    function updateCreatorPercent(uint8 _creatorPercent) external  onlyOwner() {
        _setFee(_creatorPercent);
    }

    function updateURI(string memory newURI) external  onlyOwner() {       
        string memory oldURI = _URI;
        _setURI(newURI);

        emit UpdatedURI(oldURI, newURI);
    }

 

    function _setURI(string memory newURI) internal {
        _URI = newURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return _URI;
    }

    function updateNFTPrice(uint256 amount) external onlyOwner() {
        pricePerUnit = amount;
    }

    function _setFee(uint8 _creatorPercent) internal {
        require(_creatorPercent <= CREATOR_PERCENT_MAX, "OrboFi: INVALID_CREATOR_SHARE");
        creatorPercent = _creatorPercent;
        emit FeeUpdated(_creatorPercent);
    }


      // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}