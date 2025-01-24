// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {BananaToken} from "src/token/BananaToken.sol";

contract SetTokenOwner is Script {
    function _deploymentWallet() internal virtual returns (Vm.Wallet memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        return wallet;
    }

    function run() public {
        Vm.Wallet memory wallet = _deploymentWallet();
        address newOwner = vm.envAddress("NEW_OWNER");
        address token = vm.envAddress("TOKEN");

        vm.startBroadcast(wallet.privateKey);

        BananaToken(token).transferOwnership(newOwner);

        vm.stopBroadcast();
    }
}
