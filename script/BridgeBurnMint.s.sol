// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {IBurnMint} from "src/burnMint/IBurnMint.sol";
import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract BridgeBurnMint is Script {
    function _deploymentWallet() internal virtual returns (Vm.Wallet memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        return wallet;
    }

    function run() public {
        Vm.Wallet memory wallet = _deploymentWallet();
        address burnMint = vm.envAddress("BURN_MINT");
        uint16 recipientChain = uint16(vm.envUint("TO_CHAIN"));

        vm.startBroadcast(wallet.privateKey);

        IBurnMint bm = IBurnMint(burnMint);
        IERC20(bm.token()).approve(burnMint, 100);
        uint256 cost = bm.quotePrice(recipientChain);
        bm.transfer{value: cost}(100, recipientChain, toWormholeFormat(wallet.addr));

        vm.stopBroadcast();
    }
}
