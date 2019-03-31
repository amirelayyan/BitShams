pragma solidity ^0.4.4;

import "./GeneralDevice.sol";

contract IBattery is GeneralDevice {

//  int     wallet;                   // To record loss & gain
  
  //uint    volTimeOut = 5 minutes;
  uint    priceTimeOut = 5 minutes;
  
  uint    priceStatusAt;            // timestamp of the update (price)
  uint    volStatusAt;              // timestamp of the update
  uint    lastPriceQueryAt;
  uint    lastRankingAt;

  function getSalePrice() public view returns (uint prs, bool updatedOrNot);
  function getSortedPrice() external returns(uint consum, uint rank, uint tot, bool updated);
  function goNoGo(uint giveoutvol) public timed(4) returns (uint);
  function goExcess(uint vol) public timed(5) returns ( uint takeVol, uint prs);
  function getConsumption() view public returns (uint);
  function getVolumeCapacity () external view returns (uint vol, uint volAt, uint cap);
}
