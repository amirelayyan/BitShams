pragma solidity ^0.4.4;

import "./IGrid.sol";
import "./IBattery.sol";
import "./TransactLib.sol";
import "./GeneralDevice.sol";

contract GridFactory {
  mapping(address => Grid) grids;

  function GridFactory() public {}

  function createGrid(address _accountAddress) public returns (address gridAddress) {
    grids[_accountAddress] = new Grid(_accountAddress);
    return address(grids[_accountAddress]);
  }

  function getGridAddress(address _accountAddress) public constant returns (address gridAddress) {
    return grids[_accountAddress];
  }
}

contract Grid is GeneralDevice, IGrid {

  using TransactLib for *;

  uint    price;
  uint    priceFeedIn;



  function Grid(address adr) adminOnly public GeneralDevice(adr) { }   // there was no "adminOnly public"

  function setPrice(uint prs, uint prsF) public ownerOnly timed(1) {
    price = prs;
    priceFeedIn = prsF;
    priceStatusAt = now;
  }

  function getPrice() public view returns (uint prs, bool updatedOrNot) {
    prs = price;
    //prsAt = priceStatusAt;
    if (priceStatusAt + priceTimeOut < now) {
      updatedOrNot = false;
    } else {
      updatedOrNot = true;
    }
    //adr = owner;
  }
  // Does not need to be implemented if the clockLib works
  /*function needTBCharged() {
    //Grid ask if battery is actively buying energy from grid?
    uint consum;
    uint rank;
    uint tot;
    bool updated;
    uint whatDeviceAccept;
    uint receivedMoney;
    address adr;
    for (uint i = 0; i < connectedDevice[2].length; i++) {
      (consum,rank,tot,updated) = IBattery(connectedDevice[2][i]).getSortedPrice();
      if (updated && consum != 0) {
        // transaction
        adr = connectedDevice[2][i];
        whatDeviceAccept = IBattery(adr).goNoGo(posBackup);
        posBackup -= whatDeviceAccept;
        receivedMoney = whatDeviceAccept*price;
        wallet = wallet.clearMoneyTransfer(receivedMoney,adr, address(this));
      }
    }
  }*/

  function goExcess(uint vol) timed(5) public returns (uint, uint) {
    uint takeVol = vol;//.findMin(negBackup);
    // negBackup = negBackup.clearEnergyTransfer(takeVol, address(this));
    wallet -= int(takeVol*priceFeedIn);
    return (takeVol,priceFeedIn);
  }

  function goExtra(uint vol) timed(5) public returns (uint, uint) { // when houses have not sufficient energy supply from microgrid
    uint takeVol = vol;//.findMin(posBackup);
    // posBackup -= takeVol;
    wallet += int(takeVol*price);
    // wallet = wallet.clearMoneyTransfer(takeVol*prs,msg.sender, address(this));
    return (takeVol,price);
  }
}
