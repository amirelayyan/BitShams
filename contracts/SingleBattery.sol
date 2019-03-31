pragma solidity ^0.4.16;

import "./IBattery.sol";
import "./IPV.sol";
import "./IGrid.sol";
import "./IHouseE.sol";
import "./IHeatPump.sol";
import "./GeneralDevice.sol";

import "./SortRLib.sol";
import "./SortPLib.sol"; 
import "./AdrLib.sol"; 
import "./TransactLib.sol";
import "./DeviceFactoryInterface.sol";

contract SingleBatteryFactory is SingleBatteryFactoryInterface {
  mapping(address => address) batteries;

  function SingleBatteryFactory() public {}

  function createSingleBattery(address _accountAddress, uint _capacity) public returns (address batteryAddress) {
    batteries[_accountAddress] = new SingleBattery(_accountAddress, _capacity);
    return address(batteries[_accountAddress]);
  }

  function getSingleBatteryAddress(address _accountAddress) public constant returns (address batteryAddress) {
    return batteries[_accountAddress];
  }
}

//For simplicity, we do not use the sorting functions here, as in our configuration, there is only one battery and there's only one PV connected.  

contract SingleBattery is GeneralDevice, IBattery {
  
  using AdrLib for address[];
  using TransactLib for *;
  using SortPLib for *;
  using SortRLib for *;

  uint    capacity;                 // Cap of the device
  uint    currentVolume;            // Production of electricity
  uint    consumption;                // Amount of electricity that this battery would like to buy. Will first participate in the supply competition 
                                    //and will be finally (anyway) fulfilled b either the network or from the grid...
  uint    priceForSale;
  uint    priceForBuy;              // lower than market price (ForExcessEnergy)
  uint    newCounter;

  SortPLib.PriceMap draftPriceMap;
  SortRLib.RankMap draftRankMap;

// ======= Modifiers =======

// ======= Event Logs =======

  event VolLog(address adr, uint vol, uint volAt);
  event PriceUpdate(uint updateAt);
  event TestLog_battery_1(uint consumption);
  event TestLog_battery_2(uint connection);
  // event CounterLog(uint j, uint counter, uint round);
  // event TestLog2(uint rank, uint stepNum_j);
  // event DeviceIDLog(uint deviceID);
  event TestLog_battery(uint rank, uint total, bool update);

// ======= Basic Functionalities =======

  // --- 0. Upon contract creation and configuration ---

  function SingleBattery (address adr,  uint cap) GeneralDevice(adr) adminOnly public {
    capacity = cap;
  }

  function setVolume(uint vol) public adminOnly {
    // Can only be triggered once....Should be moved into the constructor...Once the initial volumne is set, can only be changed by energy trading.
    currentVolume = vol;
    volStatusAt = now;
    VolLog(owner,vol,volStatusAt);
    return;
  }

  // --- 1. set and get the active purchase volume (if battery wants) and selling price every 15 min (or less) ---

  function setPrice(uint prsSale, uint prsBuy) public timed(1) ownerOnly {
    priceForSale = prsSale;
    priceForBuy = prsBuy;
    priceStatusAt = now;
    PriceUpdate(priceStatusAt);
    return;
  }

  function getSalePrice() public view returns (uint prs, bool updatedOrNot) { // connectedHouseOnly external
    prs = priceForSale;
    //prsAt = priceStatusAt;
    if (priceStatusAt + priceTimeOut < now) {
      updatedOrNot = false;
    } else {
      updatedOrNot = true;
    }
    //adr = owner;
  }

  function setConsumption(uint v) public timed(1) ownerOnly {
    if (currentVolume + v <= capacity) {
      consumption = v;
    } else {
      consumption = 0;
    }
    // require(currentVolume + v <= capacity);
    return;
  }

  function getConsumption() view public returns (uint) {return consumption;}

  function getVolumeCapacity () external view returns (uint vol, uint volAt, uint cap) {
    vol = currentVolume;
    volAt = volStatusAt;
    cap = capacity;
  }

  // --- 2. Battery can be considered as a house if it wants to actively purchase energy. --- 
  // ---    Ask for connected PV / batteries / grid for price of electricity supply. --- 
  // ---    Sort the list of offers. --- 

  function askForPrice() public timed(2) {
    // if (connectedDevice[1].length > 0) {
      // Battery query price info to all the connected PV/Battery. 
      uint tP = 0;
      bool tF = false;
      draftPriceMap.initPrsTable();
      for (uint i = 0; i < connectedDevice[1].length; i++) {
        (tP,tF) = IPV(connectedDevice[1][i]).getPrice();
        draftPriceMap.addToPrsTable(connectedDevice[1][i],tP,tF);
      }
      lastPriceQueryAt = now;
    // }
    return;
  }

  function sortPrice() public timed(2) {
    
    if (connectedDevice[1].length > 0) {
      draftPriceMap.sortPrsTable();
    }
    return;
  }

  function getSortedPrice() external returns(uint consum, uint rank, uint tot, bool updated) {
    consum = consumption;
    (rank,tot,updated) = draftPriceMap.getPrsTable(msg.sender);
  }

  // --- 3. Battery can also provide energy to houses. --- 
  // ---    Sort the list of ranks. --- 

  function askForRank() public timed(3) {
    uint consum;
    uint rank;
    uint tot;
    bool updated;
    draftRankMap.initRnkTable();
    for (uint i = 0; i < connectedDevice[0].length; i++) {
      (consum, rank, tot, updated) = IHouseE(connectedDevice[0][i]).getSortedPrice();
      if (updated) {
        draftRankMap.addToRnkTable(connectedDevice[0][i],consum, rank, tot);
      }
    }
    for (i = 0; i < connectedDevice[3].length; i++) {
      (consum,rank,tot,updated) = IHeatPump(connectedDevice[3][i]).getSortedPrice();
      if (updated) {
        draftRankMap.addToRnkTable(connectedDevice[3][i],consum, rank, tot);
      }
    }
    lastRankingAt = now;
    return;
  }

  function sortRank() public timed(3) {
    draftRankMap.sortRnkTable();
    return;
  }

  function getSortedRank(uint _id) view public returns(address adr, uint consum, uint rank, uint tot) {
    return draftRankMap.getSortedList(_id);
  }

  // --- 4. PV/Battery/Grid asks Battery to confirm energy transaction ---

  function goNoGo(uint giveoutvol) public timed(4) returns (uint) {
    address adrDevice = msg.sender;
    uint takeoutvol;
    require(connectedDevice[1].assertInside(adrDevice) || adrDevice == grid);
    takeoutvol = consumption.findMin(giveoutvol);
    currentVolume += takeoutvol;
    volStatusAt = now;
    VolLog(owner,currentVolume,volStatusAt);
    if (consumption > 0) {
      consumption -= takeoutvol;
    }
    // consumption = consumption.clearEnergyTransfer(takeoutvol, address(this));
    wallet += int(takeoutvol*draftPriceMap.prsTable[adrDevice].prs);
    return (takeoutvol); 
  }

  // @ param i is the current index (stage);
  //         counter is the number of transactions that have been executed/passed, ranging from 0 to (totalNumber - 1);
  function verifySellEnergy(uint i, uint counter) public timed(4) {
    uint totalNumber = draftRankMap.totalLength;

    address adr;
    uint consum;
    uint rank;
    uint tot;

    if (counter < totalNumber) {

      for (uint j = counter; j < totalNumber; j++) {
        (adr,consum,rank,tot) = getSortedRank(counter);

        if (rank == i) {
          // time to make transaction
          if (currentVolume > 0 && consum > 0) {
            initiateTransaction(counter);
          }
          counter++;
        } else if (rank < i) {
          // the transaction of this ranking has been done globally. No more transaction should be made for this ranking.
          counter++;
        } else {
          // when rank > i, need to wait
          newCounter = counter;
          return;
        }
        
      }
    }
    newCounter = counter;

    return;
  }
  
  function getNewCounter() public view returns (uint) {
    return newCounter;
  }

  function initiateTransaction(uint _id) private  { //public timed(4) returns (uint, uint)
    uint giveoutVol;
    address adr;
    uint consum;
    uint rank;
    uint tot;
    uint whatDeviceAccept;
    uint receivedMoney;
    // uint tStamp;
 
      (adr,consum,rank,tot) = getSortedRank(_id);
      giveoutVol = currentVolume.findMin(consum);
      // giveoutVol = currentVolume;
      if (connectedDevice[0].assertInside(adr)) {
        // DeviceIDLog(0);
        // (consum, tStamp)= IHouseE(adr).getConsumptionE();
        // TestLog3(consum,tStamp);
        // giveoutVol = currentVolume.findMin(consum);
        whatDeviceAccept = IHouseE(adr).goNoGo(giveoutVol);
        // TestLog3(whatDeviceAccept, giveoutVol);
        // if (currentVolume < whatDeviceAccept) { 
        //   whatDeviceAccept = currentVolume; 
        // }
        // currentVolume -= whatDeviceAccept;
        // receivedMoney = whatDeviceAccept*priceForSale;
        // wallet += int(receivedMoney);
        // wallet = wallet.clearMoneyTransfer(receivedMoney,adr, address(this));
      } else if (connectedDevice[3].assertInside(adr)) {
        // DeviceIDLog(3);
        // consum = IHeatPump(adr).getConsumptionE();
        // giveoutVol = currentVolume.findMin(consum);
        whatDeviceAccept = IHeatPump(adr).goNoGo(giveoutVol);
        if (currentVolume < whatDeviceAccept) { 
          whatDeviceAccept = currentVolume; 
        } 
        // currentVolume -= whatDeviceAccept;
        // receivedMoney = whatDeviceAccept*priceForSale;
        // wallet += int(receivedMoney);
        // wallet = wallet.clearMoneyTransfer(receivedMoney,adr, address(this));
      } else {
        // DeviceIDLog(99);
        whatDeviceAccept = 0; 
      }
      currentVolume -= whatDeviceAccept;
      receivedMoney = whatDeviceAccept*priceForSale;
      wallet += int(receivedMoney);
      volStatusAt = now;
      VolLog(owner,currentVolume,volStatusAt);
      // return(giveoutVol, whatDeviceAccept);
    //}
    return;
  }

  // --- 5. Deal with excess energy --- 

  function goExcess(uint vol) public timed(5) returns (uint takeVol, uint prs) {
    // takeVol = vol.findMin(capacity-currentVolume);
    if (currentVolume + vol <= capacity) {
      takeVol = vol;
    } else {
      takeVol = capacity - currentVolume;
    }
    currentVolume += takeVol;
    // currentVolume = currentVolume.clearExcessTransfer(takeVol, address(this));
    wallet -= int(takeVol*priceForBuy);
    return (takeVol, priceForBuy);
  }

}
