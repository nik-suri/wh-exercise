// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/interfaces/IWormhole.sol";
import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";
import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "src/burnMint/IBurnMint.sol";

abstract contract BurnMintState is IBurnMint {
    using BytesParsing for bytes;

    constructor(
        address _admin,
        address _token,
        uint16 _chainId,
        address _wormholeCore,
        address _wormholeRelayer,
        uint256 _gasLimit
    ) {
        admin = _admin;
        token = _token;
        chainId = _chainId;
        wormhole = IWormhole(_wormholeCore);
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
        gasLimit = _gasLimit;
    }

    // =============== Immutables ============================================================

    /// @dev Address of the admin
    address public immutable admin;

    /// @dev Address of the token that this NTT Manager is tied to
    address public immutable token;

    /// @dev Wormhole chain ID that the NTT Manager is deployed on.
    /// This chain ID is formatted Wormhole Chain IDs -- https://docs.wormhole.com/wormhole/reference/constants
    uint16 public immutable chainId;

    uint8 public immutable consistencyLevel;
    IWormhole public immutable wormhole;
    IWormholeRelayer public immutable wormholeRelayer;
    uint256 public immutable gasLimit;

    // =============== Storage ==============================================================

    bytes32 private constant PEERS_SLOT = bytes32(uint256(keccak256("burnmint.peers")) - 1);
    bytes32 private constant WORMHOLE_CONSUMED_VAAS_SLOT = bytes32(uint256(keccak256("burnmint.consumedVAAs")) - 1);

    function _getPeersStorage() internal pure returns (mapping(uint16 => Peer) storage $) {
        uint256 slot = uint256(PEERS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    function _getWormholeConsumedVAAsStorage() internal pure returns (mapping(bytes32 => bool) storage $) {
        uint256 slot = uint256(WORMHOLE_CONSUMED_VAAS_SLOT);
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    // =============== Getters/Setters ============================================================

    function isVAAConsumed(bytes32 hash) public view returns (bool) {
        return _getWormholeConsumedVAAsStorage()[hash];
    }

    function _setVAAConsumed(bytes32 hash) internal {
        _getWormholeConsumedVAAsStorage()[hash] = true;
    }

    // set peer
    function setPeer(uint16 peerChainId, bytes32 peerContract) public onlyAdmin {
        if (peerChainId == 0) {
            revert InvalidPeerChainIdZero();
        }
        if (peerContract == bytes32(0)) {
            revert InvalidPeerZeroAddress();
        }
        if (peerChainId == chainId) {
            revert InvalidPeerSameChainId();
        }

        _getPeersStorage()[peerChainId].peerAddress = peerContract;
    }

    // get peer
    function getPeer(uint16 chainId_) public view returns (Peer memory) {
        return _getPeersStorage()[chainId_];
    }

    // =============== VAA Validation ============================================================

    function _verifyMessage(bytes memory encodedMessage) internal returns (bytes memory) {
        // verify VAA against Wormhole Core Bridge contract
        (IWormhole.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(encodedMessage);

        // ensure that the VAA is valid
        if (!valid) {
            revert InvalidVaa(reason);
        }

        // ensure that the message came from a registered peer contract
        if (!_verifyBridgeVM(vm)) {
            revert InvalidPeer(vm.emitterChainId, vm.emitterAddress);
        }

        // save the VAA hash in storage to protect against replay attacks.
        if (isVAAConsumed(vm.hash)) {
            revert TransferAlreadyCompleted(vm.hash);
        }
        _setVAAConsumed(vm.hash);

        return vm.payload;
    }

    function _verifyBridgeVM(IWormhole.VM memory vm) internal view returns (bool) {
        return getPeer(vm.emitterChainId).peerAddress == vm.emitterAddress;
    }

    // =============== MODIFIERS ===============================================

    /**
     * @dev Throws if called by any account other than the admin.
     */
    modifier onlyAdmin() {
        _checkAdmin();
        _;
    }

    /**
     * @dev Throws if the sender is not the admin.
     */
    function _checkAdmin() internal view virtual {
        if (admin != msg.sender) {
            revert UnauthorizedAccount(msg.sender);
        }
    }

    modifier onlyRelayer() {
        if (msg.sender != address(wormholeRelayer)) {
            revert CallerNotRelayer(msg.sender);
        }
        _;
    }

    // =============== ENCODING/DECODING ===============================================

    function _encodeBurnMintMessage(BurnMintMessage memory m) public pure returns (bytes memory encoded) {
        return abi.encodePacked(m.sender, m.amount, m.sourceToken, m.to, m.toChain);
    }

    function _parseBurnMintMessage(bytes memory encoded) public pure returns (BurnMintMessage memory burnMintMessage) {
        uint256 offset = 0;
        (burnMintMessage.sender, offset) = encoded.asBytes32Unchecked(offset);
        (burnMintMessage.amount, offset) = encoded.asUint256Unchecked(offset);
        (burnMintMessage.sourceToken, offset) = encoded.asBytes32Unchecked(offset);
        (burnMintMessage.to, offset) = encoded.asBytes32Unchecked(offset);
        (burnMintMessage.toChain, offset) = encoded.asUint16Unchecked(offset);
    }
}
