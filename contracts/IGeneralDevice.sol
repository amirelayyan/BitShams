pragma solidity ^0.4.16;

contract IGeneralDevice {
  function setTimerAdr(address adr) public;
  function getWallet() public view returns (int);
  function setGridAdr(address adr) public;
  function getTimerAddress() public view returns (address);
  function getGridAdr() public returns (address);
  function addConnectedDevice(uint a, address adr) public;
  function getTimerStatus() internal returns (uint);
}
