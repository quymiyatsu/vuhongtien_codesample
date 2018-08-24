pragma solidity ^0.4.13;

import "./RTHToken.sol";

contract owned {
    address owner;

    modifier onlyowner() {
        if (msg.sender == owner) {
            _;
        }
    }

    function owned() {
        owner = msg.sender;
    }
}

contract Market is owned {

    using SafeMath for uint256;
    struct Offer {

        uint amount;
        address who;
    }

    struct OrderBook {

        uint higherPrice;
        uint lowerPrice;

        mapping (uint => Offer) offers;

        uint offers_key;
        uint offers_length;
    }

    struct Token {
        address tokenContract;
        string symbolName;
        //0. Buy
        //1. Sell
        mapping (uint => OrderBook)[2] book;
        uint[2] lowestPrice;
        uint[2] highestPrice;
        uint[2] amountPrices;
    }


    mapping (uint8 => Token) tokens;

    uint8 symbolNameIndex;

    mapping (address => mapping (uint8 => uint)) tokenBalanceForAddress;

    mapping (address => uint) balanceEthForAddress;




    // EVENTS

    //EVENTS for Deposit/withdrawal
    event DepositForTokenReceived(address indexed _from, uint indexed _symbolIndex, uint _amount, uint _timestamp);
    event WithdrawalToken(address indexed _to, uint indexed _symbolIndex, uint _amount, uint _timestamp);
    event DepositForEthReceived(address indexed _from, uint _amount, uint _timestamp);
    event WithdrawalEth(address indexed _to, uint _amount, uint _timestamp);

    //events for orders
    event BuyOrderStatus(uint indexed amountBuyPrices, uint lowestBuyPrice, uint highestBuyPrice, uint priceInWei);
    event LimitSellOrderCreated(uint indexed _symbolIndex, address indexed _who, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event SellOrderFulfilled(uint indexed _symbolIndex, uint _amount, uint _priceInWei, uint _orderKey);
    event SellOrderCanceled(uint indexed _symbolIndex, uint _priceInWei, uint _orderKey);

    event SellOrderStatus(uint indexed amountSellPrices, uint lowestSellPrice, uint highestSellPrice, uint priceInWei);
    event LimitBuyOrderCreated(uint indexed _symbolIndex, address indexed _who, uint _amountTokens, uint _priceInWei, uint _orderKey);
    event BuyOrderFulfilled(uint indexed _symbolIndex, uint _amount, uint _priceInWei, uint _orderKey);
    event BuyOrderCanceled(uint indexed _symbolIndex, uint _priceInWei, uint _orderKey);

    event AddBuy(uint offers_length, uint offers_key);
    event AddSell(uint offers_length, uint offers_key, uint balance);
    //EVENTS for management
    event TokenAddedToSystem(uint _symbolIndex, string _token, uint _timestamp);

    // DEPOSIT AND WITHDRAWAL ETHER 
    function depositEther() payable {
        balanceEthForAddress[msg.sender].add(msg.value);
    }

    function withdrawEther(uint amountInWei) {
        balanceEthForAddress[msg.sender].sub(amountInWei);
        msg.sender.transfer(amountInWei);
    }

    function getEthBalanceInWei() constant returns (uint){
        return balanceEthForAddress[msg.sender];
    }

    // TOKEN MANAGEMENT 
    function addToken(string symbolName, address erc20TokenAddress) onlyowner {
        require(!hasToken(symbolName));
        symbolNameIndex++;
        tokens[symbolNameIndex].symbolName = symbolName;
        tokens[symbolNameIndex].tokenContract = erc20TokenAddress;
    }

    function hasToken(string symbolName) constant returns (bool) {
        uint8 index = getSymbolIndex(symbolName);
        if (index == 0) {
            return false;
        }
        return true;
    }


    function getSymbolIndex(string symbolName) internal returns (uint8) {
        for (uint8 i = 1; i <= symbolNameIndex; i++) {
            if (stringsEqual(tokens[i].symbolName, symbolName)) {
                return i;
            }
        }
        return 0;
    }


    function getSymbolIndexOrThrow(string symbolName) returns (uint8) {
        uint8 index = getSymbolIndex(symbolName);
        require(index > 0);
        return index;
    }

    // DEPOSIT AND WITHDRAWAL TOKEN
    function depositToken(string symbolName, uint amount) {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        require(tokens[symbolNameIndex].tokenContract != address(0));

        ERC20 token = ERC20(tokens[symbolNameIndex].tokenContract);

        require(token.transferFrom(msg.sender, address(this), amount) == true);
        tokenBalanceForAddress[msg.sender][symbolNameIndex].add(amount);
    }

    function withdrawToken(string symbolName, uint amount) {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        require(tokens[symbolNameIndex].tokenContract != address(0));

        ERC20Basic token = ERC20Basic(tokens[symbolNameIndex].tokenContract);

        tokenBalanceForAddress[msg.sender][symbolNameIndex].sub(amount);
        require(token.transfer(msg.sender, amount) == true);
    }

    function getBalance(string symbolName) constant returns (uint) {
        uint8 symbolNameIndex = getSymbolIndexOrThrow(symbolName);
        return tokenBalanceForAddress[msg.sender][symbolNameIndex];
    }

    // ORDER BOOK - BID ORDERS 
    function getBuyOrderBook(string symbolName) constant returns (uint[], uint[]) {
        return getBook(symbolName, 0);

    }

    // ORDER BOOK - ASK ORDERS 
    function getSellOrderBook(string symbolName) constant returns (uint[], uint[]) {
        return getBook(symbolName, 1);
    }

    function getBook(string symbolName, uint i) internal constant returns (uint[], uint[]) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint[] memory arrPrices = new uint[](tokens[tokenNameIndex].amountPrices[i]);
        uint[] memory arrVolumes = new uint[](tokens[tokenNameIndex].amountPrices[i]);
        uint whilePrice = tokens[tokenNameIndex].lowestPrice[i];
        uint counter = 0;
        if (tokens[tokenNameIndex].lowestPrice[i] > 0) {
            while (whilePrice <= tokens[tokenNameIndex].highestPrice[i]) {
                arrPrices[counter] = whilePrice;
                uint volumeAtPrice = 0;
                uint offers_key = 0;

                offers_key = tokens[tokenNameIndex].book[i][whilePrice].offers_key;
                while (offers_key != 0 && offers_key <= tokens[tokenNameIndex].book[i][whilePrice].offers_length) {
                    volumeAtPrice += tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount;
                    offers_key++;
                }

                arrVolumes[counter] = volumeAtPrice;

                //next whilePrice
                if (tokens[tokenNameIndex].book[i][whilePrice].higherPrice == whilePrice) {
                    break;
                }
                else {
                    whilePrice = tokens[tokenNameIndex].book[i][whilePrice].higherPrice;
                }
                counter++;

            }
        }

        return (arrPrices, arrVolumes);

    }


    // NEW ORDER - BID ORDER
    function buyToken(string symbolName, uint priceInWei, uint amount) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint total_amount_ether_necessary = 0;
        uint i = 1;
        SellOrderStatus(tokens[tokenNameIndex].amountPrices[i], tokens[tokenNameIndex].lowestPrice[i], tokens[tokenNameIndex].highestPrice[i], priceInWei);
        if(tokens[tokenNameIndex].amountPrices[i] == 0 || tokens[tokenNameIndex].lowestPrice[1] > priceInWei){
            total_amount_ether_necessary = amount.mul(priceInWei);
            balanceEthForAddress[msg.sender].sub(total_amount_ether_necessary);

            //add the order to the orderBook
            addOffer(tokenNameIndex, priceInWei, amount, msg.sender, 0);

            //emit the event.
            uint offers_length = tokens[tokenNameIndex].book[0][priceInWei].offers_length;
            LimitBuyOrderCreated(tokenNameIndex, msg.sender, amount, priceInWei, offers_length);
        }else{
            //1. Find "cheapest sell price < buy price"
            //2. Buy up every sell order from that till sell price > buy price
            //3. If still smt remaining -> create a buy order 
            
            uint total_amount_ether_available = 0;
            uint whilePrice = tokens[tokenNameIndex].lowestPrice[i];
            uint amountNecessary = amount;
            uint offers_key;
            while(whilePrice != 0 && whilePrice <= priceInWei && amountNecessary > 0){ //start with the lowest sell price.
                offers_key = tokens[tokenNameIndex].book[i][whilePrice].offers_key;
                while (offers_key <= tokens[tokenNameIndex].book[i][whilePrice].offers_length && amountNecessary >0 ){//and the first order (FIFO)
                    uint volumeAtPriceFromAddress = tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount;
                    //Two choices from here:
                    //1) one person offers not enough volume to fulfill the market order - we use it up completely and move on to the next person who offers the symbolName
                    //2) else: we make use of parts of what a person is offering - lower his amount, fulfill out order.
                    if(volumeAtPriceFromAddress <= amountNecessary){
                        total_amount_ether_available = volumeAtPriceFromAddress.mul(whilePrice);
                        //first deduct the amount of ether from our balance
                        balanceEthForAddress[msg.sender].sub(total_amount_ether_available);

                        //this guy offers less or equal the volume that we ask for, so we use it up completely.
                        tokenBalanceForAddress[msg.sender][tokenNameIndex].add(volumeAtPriceFromAddress);
                        tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount = 0;
                        balanceEthForAddress[tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].who].add(total_amount_ether_available);
                        tokens[tokenNameIndex].book[i][whilePrice].offers_key++;
                        // SellOrderFulfilled(tokenNameIndex, volumeAtPriceFromAddress, whilePrice, offers_key);
                        amountNecessary -= volumeAtPriceFromAddress;
                    }else{
                        total_amount_ether_necessary = amountNecessary.mul(whilePrice);

                        //first deduct the amount of ether from our balance
                        balanceEthForAddress[msg.sender].sub(total_amount_ether_necessary);
                        tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount.sub(amountNecessary);
                        balanceEthForAddress[tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].who].add(total_amount_ether_necessary);
                        tokenBalanceForAddress[msg.sender][tokenNameIndex].add(amountNecessary);
                        amountNecessary = 0;

                        //we have fulfilled our order
                        SellOrderFulfilled(tokenNameIndex, amountNecessary, whilePrice, offers_key);
                    }
                    //if it was the last offer for that price, we have to set the curBuyPrice now lower. Additionally we have one offer less...
                    if(offers_key == tokens[tokenNameIndex].book[i][whilePrice].offers_length &&
                        tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount == 0){
                        tokens[tokenNameIndex].amountPrices[i]--;
                        if (whilePrice == tokens[tokenNameIndex].book[i][whilePrice].higherPrice) {
                            tokens[tokenNameIndex].lowestPrice[i] = 0;
                            //we have reached the last price
                        }
                        else {
                            tokens[tokenNameIndex].lowestPrice[i] = tokens[tokenNameIndex].book[i][whilePrice].higherPrice;
                        }
                        tokens[tokenNameIndex].book[i][whilePrice].offers_length = 0;
                        tokens[tokenNameIndex].book[i][whilePrice].offers_key = 0;
                    }
                    offers_key++;
                }
                whilePrice = tokens[tokenNameIndex].lowestPrice[i];
            }
            if (amountNecessary > 0) {
                buyToken(symbolName, priceInWei, amountNecessary);
                //add a limit order!
            }
            SellOrderStatus(tokens[tokenNameIndex].amountPrices[i], tokens[tokenNameIndex].lowestPrice[i], tokens[tokenNameIndex].highestPrice[i], priceInWei);
        } 
        

    }

    // NEW ORDER - ASK ORDER
    function sellToken(string symbolName, uint priceInWei, uint amount) {
        uint8 tokenNameIndex = getSymbolIndexOrThrow(symbolName);
        uint total_amount_ether_necessary = 0;
        uint total_amount_ether_available = 0;
        uint i = 0;
        BuyOrderStatus(tokens[tokenNameIndex].amountPrices[i], tokens[tokenNameIndex].lowestPrice[i], tokens[tokenNameIndex].highestPrice[i], priceInWei);
        //if we have enough ether, we can buy that:
        

        if (tokens[tokenNameIndex].amountPrices[i] == 0 || tokens[tokenNameIndex].highestPrice[i] < priceInWei) {
            total_amount_ether_necessary = amount.mul(priceInWei);
            tokenBalanceForAddress[msg.sender][tokenNameIndex].sub(amount);

            //add the order to the orderBook
            addOffer(tokenNameIndex, priceInWei, amount, msg.sender, 1);
            //emit the event.
            uint offers_length = tokens[tokenNameIndex].book[1][priceInWei].offers_length;
            LimitSellOrderCreated(tokenNameIndex, msg.sender, amount, priceInWei, offers_length);

        } else {
            uint whilePrice = tokens[tokenNameIndex].highestPrice[i];
            uint amountNecessary = amount;
            uint offers_key;
            while(whilePrice >= priceInWei && amountNecessary >0){ //start with highest buy price
                offers_key = tokens[tokenNameIndex].book[i][whilePrice].offers_key;
                while (offers_key <= tokens[tokenNameIndex].book[i][whilePrice].offers_length && amountNecessary >0){
                    uint volumeAtPriceFromAddress = tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount;
                    if(volumeAtPriceFromAddress <= amountNecessary){
                        total_amount_ether_available = volumeAtPriceFromAddress * whilePrice;
                        tokenBalanceForAddress[msg.sender][tokenNameIndex].sub(volumeAtPriceFromAddress);
                        tokenBalanceForAddress[tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].who][tokenNameIndex].add(volumeAtPriceFromAddress);
                        balanceEthForAddress[msg.sender].add(total_amount_ether_available);

                        tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount = 0;
                        tokens[tokenNameIndex].book[i][whilePrice].offers_key++;
                        SellOrderFulfilled(tokenNameIndex, volumeAtPriceFromAddress, whilePrice, offers_key);

                        amountNecessary -= volumeAtPriceFromAddress;
                    }else{
                        require(volumeAtPriceFromAddress - amountNecessary > 0);
                        total_amount_ether_necessary = amountNecessary.mul(whilePrice);

                        tokenBalanceForAddress[msg.sender][tokenNameIndex].sub(amountNecessary);

                        tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount -= amountNecessary;
                        balanceEthForAddress[msg.sender].add(total_amount_ether_necessary);
                        tokenBalanceForAddress[tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].who][tokenNameIndex].add(amountNecessary);
                        SellOrderFulfilled(tokenNameIndex, volumeAtPriceFromAddress, whilePrice, offers_key);
                        amountNecessary = 0;
                    }
                    if(offers_key == tokens[tokenNameIndex].book[i][whilePrice].offers_length &&
                        tokens[tokenNameIndex].book[i][whilePrice].offers[offers_key].amount == 0){
                        tokens[tokenNameIndex].amountPrices[i]--;
                        if (whilePrice == tokens[tokenNameIndex].book[i][whilePrice].lowerPrice) {
                            tokens[tokenNameIndex].highestPrice[i] = 0;
                            //we have reached the last price
                        }
                        else {
                            tokens[tokenNameIndex].highestPrice[i] = tokens[tokenNameIndex].book[i][whilePrice].lowerPrice;
                        }
                        tokens[tokenNameIndex].book[i][whilePrice].offers_length = 0;
                        tokens[tokenNameIndex].book[i][whilePrice].offers_key = 0;
                    }
                    offers_key++;
                }
                whilePrice = tokens[tokenNameIndex].highestPrice[i];
            }
            if (amountNecessary > 0) {
                sellToken(symbolName, priceInWei, amountNecessary);
                //add a limit order, we couldn't fulfill all the orders!
            }
            BuyOrderStatus(tokens[tokenNameIndex].amountPrices[i], tokens[tokenNameIndex].lowestPrice[i], tokens[tokenNameIndex].highestPrice[i], priceInWei);
        }
        
    }

    // BID LIMIT ORDER LOGIC //
    function addOffer(uint8 tokenIndex, uint priceInWei, uint amount, address who, uint i) internal {

        tokens[tokenIndex].book[i][priceInWei].offers_length++;
        tokens[tokenIndex].book[i][priceInWei].offers[tokens[tokenIndex].book[i][priceInWei].offers_length] = Offer(amount, who);
        if (tokens[tokenIndex].book[i][priceInWei].offers_length == 1){
            tokens[tokenIndex].book[i][priceInWei].offers_key = 1;
            //we have a new buy/sell order - increase the counter, so we can set the getBook array later
            tokens[tokenIndex].amountPrices[i]++;

            uint lowestPrice = tokens[tokenIndex].lowestPrice[i];
            uint highestPrice = tokens[tokenIndex].highestPrice[i];

            if (lowestPrice == 0){
                tokens[tokenIndex].highestPrice[i] = priceInWei;
                tokens[tokenIndex].lowestPrice[i] = priceInWei;

                tokens[tokenIndex].book[i][priceInWei].higherPrice = priceInWei;
                tokens[tokenIndex].book[i][priceInWei].lowerPrice = 0;
            }else if(lowestPrice > priceInWei){
                tokens[tokenIndex].lowestPrice[i] = priceInWei;

                tokens[tokenIndex].book[i][priceInWei].higherPrice = lowestPrice;
                tokens[tokenIndex].book[i][priceInWei].lowerPrice = 0;

                tokens[tokenIndex].book[i][lowestPrice].lowerPrice = priceInWei;
            }else if(highestPrice < priceInWei){
                tokens[tokenIndex].highestPrice[i] = priceInWei;

                tokens[tokenIndex].book[i][priceInWei].higherPrice = priceInWei;
                tokens[tokenIndex].book[i][priceInWei].lowerPrice = highestPrice;

                tokens[tokenIndex].book[i][highestPrice].higherPrice = priceInWei;
            }else {
                uint max = tokens[tokenIndex].highestPrice[i];
                bool weFoundIt = false;
                while (max > 0 && !weFoundIt){
                    if (max < priceInWei && tokens[tokenIndex].book[i][max].higherPrice > priceInWei){
                        tokens[tokenIndex].book[i][priceInWei].lowerPrice = max;
                        tokens[tokenIndex].book[i][priceInWei].higherPrice = tokens[tokenIndex].book[i][max].higherPrice;

                        tokens[tokenIndex].book[i][tokens[tokenIndex].book[i][max].higherPrice].lowerPrice = priceInWei;
                        tokens[tokenIndex].book[i][max].higherPrice = priceInWei;

                        //set we found it.
                        weFoundIt = true;
                    }
                    max = tokens[tokenIndex].book[i][max].lowerPrice;
                }
            }
        }
        if (i==0){
            AddBuy(tokens[tokenIndex].book[i][priceInWei].offers_length,tokens[tokenIndex].book[i][priceInWei].offers_key);
            BuyOrderStatus(tokens[tokenIndex].amountPrices[i], tokens[tokenIndex].lowestPrice[i], tokens[tokenIndex].highestPrice[i], priceInWei);
        }else {
            AddSell(tokens[tokenIndex].book[i][priceInWei].offers_length,tokens[tokenIndex].book[i][priceInWei].offers_key, tokenBalanceForAddress[msg.sender][tokenIndex]);
            SellOrderStatus(tokens[tokenIndex].amountPrices[i], tokens[tokenIndex].lowestPrice[i], tokens[tokenIndex].highestPrice[i], priceInWei);
        }
    }


    
    // CANCEL LIMIT ORDER LOGIC
    function cancelOrder(string symbolName, bool isSellOrder, uint priceInWei, uint offerKey) {
    }

    function getTokensLength() constant returns(uint8){
        return symbolNameIndex;
    }
    
    function getToken(uint8 index) constant returns (string, address){
        require(index <= symbolNameIndex && tokens[symbolNameIndex].tokenContract != address(0));
        return(tokens[index].symbolName, tokens[index].tokenContract);
    }



    // STRING COMPARISON FUNCTION
    function stringsEqual(string storage _a, string memory _b) internal returns (bool) {
        bytes storage a = bytes(_a);
        bytes memory b = bytes(_b);
        if (a.length != b.length) {
            return false;
        }
        
        for (uint i = 0; i < a.length; i ++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }


}