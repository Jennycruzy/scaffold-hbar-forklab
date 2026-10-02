// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";
import {Hsc} from "hedera-forking/Hsc.sol";
interface IP { function getReserves() external view returns (uint112,uint112,uint32); function token0() external view returns (address); }
interface IE { function balanceOf(address) external view returns (uint); }
contract PairTest is Test {
  function test_pair() public {
    Hsc.htsSetup();
    address pair = 0xdB34c1Ef944883f0e5A2fC18B6C1978B088bD31d;
    (uint r0, uint r1,) = IP(pair).getReserves();
    address t0 = IP(pair).token0();
    string memory tpl = "0x6080604052348015600f57600080fd5b506000610167905077618dc65efefefefefefefefefefefefefefefefefefefefe600052366000602037600080366018016008845af43d806000803e8160008114605857816000f35b816000fdfea2646970667358221220d8378feed472ba49a0005514ef7087017f707b45fb9bf56bb81bb93ff19a238b64736f6c634300080b0033";
    vm.etch(t0, vm.parseBytes(vm.replace(tpl, "fefefefefefefefefefefefefefefefefefefefe", vm.replace(vm.toString(t0),"0x",""))));
    console.log("token0", t0); console.log("reserve0", r0); console.log("reserve1", r1);
    console.log("pair bal token0 (emulated)", IE(t0).balanceOf(pair));
  }
}
