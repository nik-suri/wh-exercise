// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IMintingToken} from "src/token/IMintingToken.sol";

contract SetTokenMinter is Script {
    function _deploymentWallet() internal virtual returns (Vm.Wallet memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        return wallet;
    }

    function run() public {
        Vm.Wallet memory wallet = _deploymentWallet();
        address newMinter = vm.envAddress("NEW_MINTER");
        address token = vm.envAddress("TOKEN");

        vm.startBroadcast(wallet.privateKey);

        IMintingToken(token).setMinter(newMinter);

        vm.stopBroadcast();
    }
}
