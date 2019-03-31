pragma solidity ^0.4.16;

import "./IWaterTank.sol";
import "./IHouseH.sol";
import "./IHouseE.sol";
import "./IHeatPump.sol";
import "./GeneralDevice.sol";

import "./PriceLib.sol";
import "./DeviceFactoryInterface.sol";

contract SingleWaterTankFactory is SingleWaterTankFactoryInterface {
  mapping(address => SingleWaterTank) watertanks;

  function SingleWaterTankFactory() public {}

  function createSingleWaterTank(address _accountAddress, uint _capacity, bool _waterType) public returns (address watertankAddress) {
    SingleWaterTank _singleWaterTank = new SingleWaterTank(_accountAddress, _capacity, _waterType);
    watertanks[_accountAddress] = _singleWaterTank;
    return _singleWaterTank;
  }

  function getSingleWaterTankAddress(address _accountAddress) public constant returns (address watertankAddress) {
    return watertanks[_accountAddress];
  }
}

contract SingleWaterTank is GeneralDevice, IWaterTank {
  
  using PriceLib for *;

  uint    capacity;                 // maximum volume of water
  uint    currentVolume;            // current volume of water
  // uint    previousVolume;
  uint    consumption;              // amount of water that needs to be supplied by HP (estimed by the water tank) for the next 10 min
  uint    price;
  bool    waterType;                // two types of water : false - medium temperature and true - high temperature
  mapping(uint=>uint) volMap;

  PriceLib.PriceMap prsMap;

// ======= Modifiers =======

// ======= Event Logs =======

  event VolLog(address adr, uint vol, uint volAt);
  event PrsLog(uint price, uint priceAt);
  event ConsumptionUpdate(uint updateAt);
  // event TestLog(uint tl, uint readytoSell);

// ======= Basic Functionalities =======

  // --- 0. Upon contract creation and configuration ---

  function SingleWaterTank (address adr,  uint cap, bool wType) GeneralDevice(adr) public adminOnly {
    capacity = cap;
    waterType = wType;
  }

  function setVolume(uint vol) public adminOnly {
    // Can only be triggered once....Should be moved into the constructor...Once the initial volumne is set, can only be changed by energy trading.
    // previousVolume = currentVolume;
    currentVolume = vol;
    volStatusAt = now;
    VolLog(owner,vol,volStatusAt);
    return;
  }

  function getVolume() external view returns (uint) {
    return currentVolume;
  }

  // --- 1. set and get the active purchase volume (if battery wants) and selling price every 15 min (or less) ---

  function setConsumption(uint consum) public timed(1) ownerOnly {
    consumption = consum;
    consumStatusAt = now;
    ConsumptionUpdate(consumStatusAt);
    return;
  }

  function getConsumption() public view returns (uint consum, bool updatedOrNot) { // connectedHouseOnly external
    consum = consumption;
    if (consumStatusAt + consumTimeOut < now) {
      updatedOrNot = false;
    } else {
      updatedOrNot = true;
    }
  }

  // --- 2. ask HP for the last price that it set ---
  // ---    also calculate the new price ---

  function askForPrice() public timed(2) {
    uint tP = 0;
    bool tF = false;
    //prsMap.initPrsTable();
    for (uint i = 0; i < connectedDevice[3].length; i++) {
      (tP,tF) = IHeatPump(connectedDevice[3][i]).getPrice();
      prsMap.setPrice(connectedDevice[3][i],i,tP,tF);
    }
    prsMap.totalLength = connectedDevice[3].length;
    // calculate price
    // price = prsMap.calPrice(price,previousVolume,currentVolume);
    price = prsMap.calPrice(price,currentVolume);
    priceStatusAt = now;
    PrsLog(price,priceStatusAt);
    return;
  }

  function getPrice() external view returns(uint prs) {
    prs = price;
  }

  // --- 3. Water tank ask Houses for their water consumption --- 

  function askForNeed() public timed(3) { 
    uint consumMT;
    uint consumHT;
    uint consumAt;

    // draftRankMap.initRnkTable();
    for (uint i = 0; i < connectedDevice[0].length; i++) {
      (consumMT, consumHT, consumAt) = IHouseH(connectedDevice[0][i]).getConsumptionH();
      if (waterType == false) {   //Medium temperature water tank
        //draftRankMap.addToRnkTable(connectedDevice[0][i],consum, rank, tot);
        volMap[i] = consumMT;
        // TestLog(2,volMap[i]);
      } else {
        volMap[i] = consumHT;
        // TestLog(3,volMap[i]);
      }
    }
    needStatusAt = now;
    return;
  }

  // --- 4. HP sell water to water tank ---

  function goNoGo(uint giveoutvol, uint prs) public returns (uint) {  //timed(4) or timed(5)
    address adrDevice = msg.sender;
    uint takeoutvol;
    require(connectedDevice[3].assertInside(adrDevice));
    takeoutvol = consumption.findMin(giveoutvol);
    // takeoutvol = giveoutvol; // for testing
    prsMap.setVolume(adrDevice,takeoutvol);
    currentVolume += takeoutvol;
    volStatusAt = now;
    VolLog(owner,currentVolume,volStatusAt);
    consumption -= takeoutvol;
    wallet -= int(takeoutvol*prs);
    return (takeoutvol); 
  }

  // --- 4. Water tank send water to houses ---

  function sellEnergy() public timed(4) {
    uint giveoutVol;
    uint whatDeviceAccept;

    for (uint i = 0; i < connectedDevice[0].length; i++) {
      giveoutVol = currentVolume.findMin(volMap[i]);
      // TestLog(10, giveoutVol);
      whatDeviceAccept = IHouseH(connectedDevice[0][i]).goNoGoHeating(giveoutVol,price,waterType);
      // TestLog(11, whatDeviceAccept);
      currentVolume -= whatDeviceAccept;
      // TestLog(12, currentVolume);
      volStatusAt = now;
      VolLog(owner,currentVolume,volStatusAt);
      wallet += int(whatDeviceAccept * price);
      volMap[i] -= whatDeviceAccept;
    }
    return;
  }

  // // --- 5. Deal with excess energy --- 

  // function goExcess(uint vol) timed(5) returns (uint takeVol, uint prs) {
  //   prs = priceForBuy;
  //   takeVol = vol.findMin(capacity-currentVolume);
  //   currentVolume = currentVolume.clearExcessTransfer(takeVol, address(this));
  //   wallet -= int(takeVol*prs);
  // }

}
