// SPDX-License-Identifier: MIT

/*
LINEA TESTNET = 0xD6cD7CadB5f45680b847dc5Fe926230F4fbae691
""      "" UPGRADEABLE = 0xe9DF3113c2727AaBe5c1F50747c0CB6dB4f0cD0F -- non init
fuse mainnet = 0x98ce6472dd53A65381AD85cdf8AF0A7E2946a9E4
*/
pragma solidity ^0.8.17;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import"./LZO/OmniCore.sol";
import"./LZO/IONFT.sol";

// v-1.0.4 == fixes recommended => split to libs

contract ZONEPASS is Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, ERC721BurnableUpgradeable,OwnableUpgradeable, IONFT721 , ONFT721Core {
    using Counters for Counters.Counter;
    address [] internal minters;
    address internal initAcc;
    address public _feeToken;
    uint256 internal feeAmt ; // 0.1% for direct 0.01% for via minter
    uint256 internal directFee; // basefee
    bool internal d;

    struct PASSHOLDER {
        address minter;
        address holder;
        uint256 mintTime;
        uint256 lastRenewal;
        uint256 nextExpiry;
        uint256 usedSlots;
        uint256 allowedSlots;
        uint256 totalServiceUses;
        mapping(address=>uint256) _20bal; // token balances
        mapping(uint256 => Storage) _storageSlots;
    }

    struct Storage{
        bool deleted;
        string store;
        address storer;
        bytes extra;
    }

    struct Access{
        uint256 slot;
        uint256 accesees;
        address [] access;
    }
    //event MINT(address by , uint256 id);

    mapping(address => uint256) public contractAccruedFee;
    mapping(uint256 => PASSHOLDER) public _zonepassmaps;
    mapping(uint256 => Access) public storageViewAccess;
    Counters.Counter internal _tokenIdCounter;

    
    function __fx() public {
        initAcc = msg.sender;
    }

    function initialize(address weth , string memory name , string memory symbol, uint256 _minGasToTransfer , address _lzEndpoint) initializer public {
        require(msg.sender == initAcc,"not init acc");
        __ERC721_init_unchained(name, symbol);
        __ERC721Enumerable_init_unchained();
        __ERC721URIStorage_init_unchained();
        __ERC721Burnable_init_unchained();
        __Ownable_init_unchained();
        __initCore(_lzEndpoint , _minGasToTransfer);
        minters.push(msg.sender);
        _feeToken = weth;
        feeAmt = 2;
        directFee = 0.0001 ether;
        //ONFT721Core(_minGasToTransfer, _lzEndpoint);
    }

    function getIdBalance(address token , uint256 id) public view returns(uint256){
        return _zonepassmaps[id]._20bal[token];
    }

    function getInitializer() public view returns(address){
        return initAcc;
    }

    function shareStorage(uint256 id , uint256 slot , address to) public {
        require(msg.sender == _zonepassmaps[id].holder || msg.sender == _zonepassmaps[id].minter,"not owner of id ");
        require(msg.sender == _zonepassmaps[id]._storageSlots[slot].storer && _zonepassmaps[id]._storageSlots[slot].deleted == false,"no access to slot or deleted slot");
        incrementTotalServices(id);
        storageViewAccess[id].slot = slot;
        storageViewAccess[id].access.push(to);
        storageViewAccess[id].accesees ++;
        //emit SHAREVIEW(id , slot , msg.sender , to);
    }

    function changeDirectFee(uint256 newAmt) public onlyOwner{
        directFee = newAmt;
    }

    function removeShare(uint256 id , uint256 slot , address to) public {
        require(msg.sender == _zonepassmaps[id].holder || msg.sender == _zonepassmaps[id].minter,"not owner of id ");
        require(msg.sender == _zonepassmaps[id]._storageSlots[slot].storer && _zonepassmaps[id]._storageSlots[slot].deleted == false,"no access to slot or deleted slot");
        incrementTotalServices(id);
        storageViewAccess[id].slot = slot;
        
        for (uint256 i ; i<storageViewAccess[id].access.length; i++){
            address a = storageViewAccess[id].access[i];
            if(a == to){
                delete storageViewAccess[id].access[i];
                storageViewAccess[id].accesees -1;
                break;
            }
        }
        
        //storageViewAccess[id].access.push(to);
        storageViewAccess[id].accesees -1;
       // emit SHAREVIEW(id , slot , msg.sender , to);
    }

    function shareStorage_(uint256 id , uint256 slot , address to , address from) public  isMinter{
        require(from == _zonepassmaps[id].holder || from == _zonepassmaps[id].minter,"not owner of id ");
        require(from == _zonepassmaps[id]._storageSlots[slot].storer && _zonepassmaps[id]._storageSlots[slot].deleted == false,"no access to slot or deleted slot");
        incrementTotalServices(id);
        storageViewAccess[id].slot = slot;
        storageViewAccess[id].access.push(to);
        storageViewAccess[id].accesees ++;
        //emit SHAREVIEW(id , slot , from , to);
    }

    function haveStorageAccess(address user , uint256 id , uint256 slot) public view returns(bool){
        bool x = false;
        for(uint256 i ; i< storageViewAccess[id].access.length ; i++){
            address b = storageViewAccess[id].access[i];
            if(b == user && slot == storageViewAccess[id].slot){
                x = true;
                break;
            }
        }
        return x;
    }

    function getBasicInfo(uint256 id) public view returns(address, address , uint256 ,uint256 , uint256, uint256,uint256){
        PASSHOLDER storage pass = _zonepassmaps[id];
        return(
            pass.holder,
            pass.minter,
            pass.mintTime,
            pass.nextExpiry,
            pass.allowedSlots,
            pass.usedSlots,
            pass.totalServiceUses
        );
    }

    function addToStorage(string memory hash , uint256 id , bytes memory extraData , address by) public payable isMinter{
        PASSHOLDER storage pass = _zonepassmaps[id];
        uint256 a = pass.usedSlots;
        require(a <=_zonepassmaps[id].allowedSlots,"slot exceed");
        _zonepassmaps[id].usedSlots ++;
        incrementTotalServices(id);
        pass._storageSlots[a].store = hash;
        pass._storageSlots[a].extra = extraData;
        pass._storageSlots[a].storer = by;
        //emit STORAGEADD(id , a , by);
    }

    function delFromStorage(uint256 id, uint256 slot , address storer) public payable isMinter{
        PASSHOLDER storage pass = _zonepassmaps[id];
        require(pass.usedSlots <=_zonepassmaps[id].allowedSlots,"slot exceed");
        require(storer == pass._storageSlots[slot].storer && storer == pass.holder, "did not store data slot");
        pass.usedSlots - 1;
        incrementTotalServices(id);
        pass._storageSlots[slot].deleted = true;
        //emit STORAGEDEL(id , slot ,storer);
    }

    function getStorage( uint256 id , uint256 slot) public view returns(string memory , bytes memory){
        PASSHOLDER storage pass = _zonepassmaps[id];
        require((msg.sender == pass.holder && msg.sender == pass._storageSlots[slot].storer)
        ||haveStorageAccess(msg.sender , id , slot) == true,"not owner of id and slot");
        require(pass._storageSlots[slot].deleted == false,"Deleted Slot");
        return (pass._storageSlots[slot].store,pass._storageSlots[slot].extra);
    }

    function recoverData( uint256 id , uint256 slot) public payable{
        PASSHOLDER storage pass = _zonepassmaps[id];
        require(msg.sender == pass.holder || msg.sender == pass.minter,"not owner of id ");
        require(msg.sender == pass._storageSlots[slot].storer,"no access to slot");
        require(pass._20bal[_feeToken] >= directFee * 5 || IERC20(_feeToken).balanceOf(msg.sender)>= directFee * 5  ,"need fee");
        if(msg.sender == pass.holder)
        {
            pass._20bal[_feeToken] = pass._20bal[_feeToken] - (directFee * 5);
            contractAccruedFee[_feeToken] =contractAccruedFee[_feeToken] + directFee * 5;
        }
        else {
            IERC20(_feeToken).transferFrom(msg.sender , address(this), directFee * 5);
            contractAccruedFee[_feeToken] =contractAccruedFee[_feeToken] + directFee * 5;
        }
        incrementTotalServices(id);
        pass._storageSlots[slot].deleted = false;
       // emit STORAGERECOVER(id, slot ,msg.sender);
    }

    function getRecoveryFee() public view returns(uint256){
        return directFee * 5;
    }

    function getStorage_(address by, uint256 id , uint256 slot) public isMinter view returns(string memory , bytes memory){
        require(by == _zonepassmaps[id].holder && by == _zonepassmaps[id]._storageSlots[slot].storer || 
        haveStorageAccess(by , id , slot) == true,"not owner of id and slot");
        require(_zonepassmaps[id]._storageSlots[slot].deleted == false,"Deleted Slot");
        return (_zonepassmaps[id]._storageSlots[slot].store,_zonepassmaps[id]._storageSlots[slot].extra);
    }

    function incrementTotalServices(uint256 id) public isMinter{
        _zonepassmaps[id].totalServiceUses++;
    }

    function incrementServices(uint256 id , uint256 num) public isMinter{
        _zonepassmaps[id].totalServiceUses=_zonepassmaps[id].totalServiceUses + num;
    }

    function decrementServices(uint256 id , uint256 num) public isMinter{
        _zonepassmaps[id].totalServiceUses = _zonepassmaps[id].totalServiceUses - num;
    }

    function mint(address to, string memory uri) public payable isMinter {
        uint256 tokenId = _tokenIdCounter.current();
        contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
         PASSHOLDER storage pass = _zonepassmaps[tokenId];
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        pass.holder = to;
        pass.minter = to;
        pass.mintTime = block.timestamp;
        pass.nextExpiry = block.timestamp + 31536000; // one year free pass
        incrementTotalServices(tokenId);
        pass.allowedSlots = 1000;
       // emit MINT(to , tokenId);
    }

    function increaseSlots(uint256 slots, uint256 id) public isMinter{
        _zonepassmaps[id].allowedSlots = _zonepassmaps[id].allowedSlots + slots;
        //emit EXTENDSLOTS(id , slots , by);
    }

    function depositMint(address to , string memory uri  , uint256 amt) public payable isMinter{
        require(IERC20(_feeToken).balanceOf(to)>= amt,"no balance");
        contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
        IERC20(_feeToken).transferFrom(to , address(this) , amt);
        uint256 tokenId = _tokenIdCounter.current();
        _zonepassmaps[tokenId]._20bal[_feeToken] = _zonepassmaps[tokenId]._20bal[_feeToken] + amt;
        mint(to , uri);
        incrementTotalServices(tokenId);
       // emit ADDBALANCE(tokenId , _feeToken , amt , to); 
    }

    function extendPassTime(uint256 id , uint256 time) public payable isMinter {
        require(id < _tokenIdCounter.current(),"non existent id");
        contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
        _zonepassmaps[id].lastRenewal = block.timestamp;
        _zonepassmaps[id].nextExpiry = _zonepassmaps[id].nextExpiry + time;
        incrementTotalServices(id);
      //  emit EXPIRYEXTEND(id , time , by);
    }

    function boostPass(uint256 timeInWeeks ,uint256 id) public payable {
        require(IERC20(_feeToken).balanceOf(msg.sender)>= directFee * timeInWeeks,"Recharge first");
        require(msg.sender == _zonepassmaps[id].holder);
        contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
        _zonepassmaps[id]._20bal[_feeToken] = _zonepassmaps[id]._20bal[_feeToken] - (directFee * timeInWeeks);
        uint256 week = 604800;
        _zonepassmaps[id].lastRenewal = block.timestamp;
        _zonepassmaps[id].nextExpiry = _zonepassmaps[id].nextExpiry + (timeInWeeks * week);
        incrementTotalServices(id);
      //  emit EXPIRYEXTEND(id , timeInWeeks * week , by);
    }

    function deposit(uint256 id , address token , uint256 amt, address from) public payable isMinter{
        require(id < _tokenIdCounter.current(),"non existent id");
        if(token == address(0)){
            require(msg.value > amt);
            uint256 fee = msg.value - amt;
            contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + fee;
            payable(address(this)).transfer(amt);
            _zonepassmaps[id]._20bal[address(0)] = _zonepassmaps[id]._20bal[address(0)] + amt;
        } else{
            require(IERC20(token).balanceOf(from) >= amt,"no bal");
            contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
            IERC20(token).transferFrom(from , address(this) , amt);
            _zonepassmaps[id]._20bal[token] = _zonepassmaps[id]._20bal[token] + amt;
        }
            incrementTotalServices(id);
    }

    function withdraw(uint256 id , address token , uint256 amt , address to , address from) public payable isMinter{
        require(id < _tokenIdCounter.current(),"non existent id");
        require(IERC20(token).balanceOf(address(this)) >= amt && _zonepassmaps[id]._20bal[token] >= amt,"no bal");
        require( from == _zonepassmaps[id].holder,"not owner");
        contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
        if(token == address(0)){
            _zonepassmaps[id]._20bal[address(0)] = _zonepassmaps[id]._20bal[address(0)] - amt;
            payable(to).transfer(amt);
        } else {
        _zonepassmaps[id]._20bal[token] =_zonepassmaps[id]._20bal[token] - amt;
        IERC20(token).transfer(to , amt);
        }
        incrementTotalServices(id);
    }

    function idToId( uint256 fromId , uint256 toId , address token , uint256 amount) public payable isMinter{
        require(_zonepassmaps[fromId]._20bal[token] >= amount,"no bal");
        require(fromId < _tokenIdCounter.current() && toId < _tokenIdCounter.current());
        contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
        _zonepassmaps[fromId]._20bal[token] = _zonepassmaps[fromId]._20bal[token] - amount;
        _zonepassmaps[toId]._20bal[token] = _zonepassmaps[toId]._20bal[token] + amount;
        incrementTotalServices(fromId);
      //  emit IDBALTRANSFER(fromId , toId , token , amount);
    }

    function idToAddress(uint256 fromId , address toAddress , address from,address token , uint256 amt) public payable{
        require(fromId < _tokenIdCounter.current(),"non existent id");
        require(IERC20(token).balanceOf(address(this)) >= amt && _zonepassmaps[fromId]._20bal[token] >= amt ,"no bal");
        require( from == _zonepassmaps[fromId].holder,"not owner");
        contractAccruedFee[address(0)] = contractAccruedFee[address(0)] + msg.value;
        uint256 fee_ = (amt * feeAmt)/1000;
        _zonepassmaps[fromId]._20bal[token] =_zonepassmaps[fromId]._20bal[token] - amt;
        if(token == address(0)){
            payable(toAddress).transfer(amt-fee_);
            payable(_zonepassmaps[fromId].minter).transfer(fee_);
        } else{ 
        IERC20(token).transfer(toAddress , amt-fee_);
        IERC20(token).transfer(_zonepassmaps[fromId].minter , fee_);
        }
        incrementTotalServices(fromId);
    }

    function disableDirect() public onlyOwner{
        d = true;
    }

    function enableDirect() public onlyOwner{
        d = false;
    }

    function getDirect () public view returns(bool) {
        return d;
    }

    function setWeeklyFee(uint256 amount) public onlyOwner{
        directFee = amount;
    }

    function setFeeToken(address token) public onlyOwner {
        _feeToken = token;
    }

    function getFeeToken() public view returns(address){
        return _feeToken;
    }

    function getWeeklyFee() public view returns(address token , uint256 amount){
        return (_feeToken , directFee);
    }

    //enter zero address to withdraw ether;

    function withdrawContractFee(address token , uint256 amount) public onlyOwner {
        require(amount <= contractAccruedFee[token] , "No balances");
        contractAccruedFee[token] = contractAccruedFee[token] - amount;
        if(token != address(0)){
            IERC20(token).transfer(msg.sender , amount);
        }
        if(token == address(0)){
            payable(msg.sender).transfer(amount);
        }
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        _zonepassmaps[tokenId].holder = to;
    }

    function _burn(uint256 tokenId) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
        _zonepassmaps[tokenId].holder = address(0);
    }

    modifier isMinter(){
        bool minterr =false;
        for(uint256 i ; i<minters.length ; i++){
            address minter = minters[i];
            if(msg.sender == minter){
                minterr = true;
            }
        }
        require(minterr == true || msg.sender == address(this) || msg.sender == owner(),"access control denied");
        _;
    }

    function isExpired(uint256 id) public view returns(bool){
        if(block.timestamp > _zonepassmaps[id].nextExpiry){
            return true;
        }
        return false;
    }

    function addMinter(address minter_) public onlyOwner{
        minters.push(minter_);
    }
    
    function removeMinter(address minter_) public onlyOwner{
        for(uint256 i; i< minters.length;i++){
            address m = minters[i];
            if(minter_ == m){
                delete minters[i];
                
            }
        }
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

   function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, ONFT721Core, IERC165) returns (bool) {
        return  super.supportsInterface(interfaceId) || interfaceId == type(IONFT721).interfaceId;
    }

    //overrides
    function _debitFrom(
        address _from,
        uint16 ,
        bytes memory,
        uint _tokenId
    ) internal virtual override {
        require(_isApprovedOrOwner(_msgSender(), _tokenId), "ONFT721: send caller is not owner nor approved");
        require(ERC721Upgradeable.ownerOf(_tokenId) == _from, "ONFT721: send from incorrect owner");
        _transfer(_from, address(this), _tokenId);
    }

    function _creditTo(
        uint16 ,
        address _toAddress,
        uint _tokenId
    ) internal virtual override {
        require(!_exists(_tokenId) || (_exists(_tokenId) && ERC721Upgradeable.ownerOf(_tokenId) == address(this)));
        if (!_exists(_tokenId)) {
            _safeMint(_toAddress, _tokenId);
        } else {
            _transfer(address(this), _toAddress, _tokenId);
        }
    }
}