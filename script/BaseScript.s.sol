pragma solidity =0.7.6;

import {Script} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract BaseScript is Script, StdCheats {
    address public deployer = vm.envAddress("LOCAL_DEPLOYER");

    function dealToken(address token, address to, uint256 give) public {
        super.deal(token, to, give);
    }
}
