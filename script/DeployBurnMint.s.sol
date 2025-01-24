// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {BurnMint} from "src/burnMint/BurnMint.sol";

contract DeployBurnMint is Script {
    function _deploymentWallet() internal virtual returns (Vm.Wallet memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        return wallet;
    }

    function run() public returns (BurnMint) {
        Vm.Wallet memory wallet = _deploymentWallet();
        address admin = wallet.addr;
        address token = vm.envAddress("TOKEN");
        uint16 chainId = uint16(vm.envUint("CHAIN_ID"));
        address whCore = vm.envAddress("WH_CORE");
        address whRelayer = vm.envAddress("WH_RELAYER");

        vm.startBroadcast(wallet.privateKey);

        // deploy, hardcoding gas limit to 500,000
        BurnMint bm = new BurnMint(admin, token, chainId, whCore, whRelayer, 500_000);

        vm.stopBroadcast();

        return (bm);
    }
}
