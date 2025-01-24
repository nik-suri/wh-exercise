// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {BananaToken} from "src/token/BananaToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployToken is Script {
    function _deploymentWallet() internal virtual returns (Vm.Wallet memory) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        Vm.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        return wallet;
    }

    function run() public returns (BananaToken) {
        Vm.Wallet memory wallet = _deploymentWallet();
        address admin = wallet.addr;

        vm.startBroadcast(wallet.privateKey);

        address implementation = address(new BananaToken());
        bytes memory data = abi.encodeCall(BananaToken.initialize, (admin));
        address proxy = address(new ERC1967Proxy(implementation, data));
        BananaToken t = BananaToken(proxy);

        // mint supply of 10 million to admin
        t.setMinter(admin);
        t.mint(admin, 10_000_000e18);

        vm.stopBroadcast();

        return t;
    }
}
