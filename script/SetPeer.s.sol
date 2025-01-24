// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IBurnMint} from "src/burnMint/IBurnMint.sol";
import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";

contract SetPeer is Script {
    function _deploymentWallet() internal virtual returns (Vm.Wallet memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        return wallet;
    }

    function run() public {
        Vm.Wallet memory wallet = _deploymentWallet();
        address burnMint = vm.envAddress("BURN_MINT");
        address peerAddress = vm.envAddress("PEER");
        uint16 chainId = uint16(vm.envUint("CHAIN"));

        vm.startBroadcast(wallet.privateKey);

        IBurnMint(burnMint).setPeer(chainId, toWormholeFormat(peerAddress));

        vm.stopBroadcast();
    }
}
