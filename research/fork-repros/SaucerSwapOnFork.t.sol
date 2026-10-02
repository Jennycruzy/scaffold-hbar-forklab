// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";
import {Hsc} from "hedera-forking/Hsc.sol";
interface IRouter { function swapExactETHForTokens(uint,address[] calldata,address,uint) external payable returns (uint[] memory);
  function getAmountsOut(uint,address[] calldata) external view returns (uint[] memory); }
interface IERC20 { function balanceOf(address) external view returns (uint); function approve(address,uint) external returns (bool); }
interface IR2 { function swapExactTokensForTokens(uint,uint,address[] calldata,address,uint) external returns (uint[] memory); }
contract SaucerTest is Test {
  address constant ROUTER = address(0x2e7a5d);
  address constant WHBAR = address(0x163b5a);
  address constant USDC  = address(0x6f89a);
  function setUp() public { Hsc.htsSetup(); _proxy(USDC); _proxy(WHBAR); _proxy(SAUCE); }
  address constant SAUCE = address(0xb2ad5);
  function _proxy(address t) internal {
    string memory tpl = "0x6080604052348015600f57600080fd5b506000610167905077618dc65efefefefefefefefefefefefefefefefefefefefe600052366000602037600080366018016008845af43d806000803e8160008114605857816000f35b816000fdfea2646970667358221220d8378feed472ba49a0005514ef7087017f707b45fb9bf56bb81bb93ff19a238b64736f6c634300080b0033";
    string memory a = vm.replace(vm.toString(t), "0x", "");
    vm.etch(t, vm.parseBytes(vm.replace(tpl, "fefefefefefefefefefefefefefefefefefefefe", a)));
  }
  function test_quote() public view {
    address[] memory p = new address[](2); p[0]=WHBAR; p[1]=USDC;
    uint[] memory a = IRouter(ROUTER).getAmountsOut(100e8, p);
    console.log("100 HBAR ->", a[1]);
  }
  function test_usdcRead() public view { console.log("usdc bal of router", IERC20(USDC).balanceOf(ROUTER)); }
  function test_swap() public {
    address u = makeAddr("u"); vm.deal(u, 1000e18);
    address[] memory p = new address[](2); p[0]=WHBAR; p[1]=USDC;
    vm.prank(u);
    IRouter(ROUTER).swapExactETHForTokens{value: 100e8}(0, p, u, block.timestamp+60);
    console.log("got usdc", IERC20(USDC).balanceOf(u));
  }

  function test_tokenSwap() public {
    address u = makeAddr("u2");
    deal(USDC, u, 50e6);
    console.log("u usdc", IERC20(USDC).balanceOf(u));
    address[] memory p = new address[](3); p[0]=USDC; p[1]=WHBAR; p[2]=SAUCE;
    vm.startPrank(u);
    IERC20(USDC).approve(address(0x2e7a5d), 50e6);
    IR2(address(0x2e7a5d)).swapExactTokensForTokens(50e6, 0, p, u, block.timestamp+60);
    vm.stopPrank();
    console.log("u sauce", IERC20(SAUCE).balanceOf(u));
  }
}
