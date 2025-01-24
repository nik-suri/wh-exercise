// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "src/token/IMintingToken.sol";
import "src/burnMint/BurnMintState.sol";

// integrates with wormhole for burn/mint token transfers
contract BurnMint is BurnMintState, IWormholeReceiver {
    using SafeERC20 for IERC20;

    constructor(
        address _admin,
        address _token,
        uint16 _chainId,
        address _wormholeCore,
        address _wormholeRelayer,
        uint256 _gasLimit
    ) BurnMintState(_admin, _token, _chainId, _wormholeCore, _wormholeRelayer, _gasLimit) {}

    // quote delivery price
    function quotePrice(uint16 recipientChain) external view returns (uint256) {
        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(recipientChain, 0, gasLimit);
        return cost;
    }

    // transfer
    function transfer(uint256 amount, uint16 recipientChain, bytes32 recipient) external payable returns (uint64) {
        // validations
        if (amount == 0) {
            revert ZeroAmount();
        }

        if (recipient == bytes32(0)) {
            revert InvalidRecipient();
        }

        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(recipientChain, 0, gasLimit);
        // check up front that msg.value will cover the delivery price
        if (msg.value < cost) {
            revert DeliveryPaymentTooLow(cost, msg.value);
        }

        // use transferFrom to pull tokens from the user
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // burn tokens
        ERC20Burnable(token).burn(amount);

        // format message
        // construct the NttManagerMessage payload
        bytes memory encodedPayload = _encodeBurnMintMessage(
            BurnMintMessage(toWormholeFormat(msg.sender), amount, toWormholeFormat(token), recipient, recipientChain)
        );

        uint64 sequence = wormholeRelayer.sendToEvm{value: cost}(
            recipientChain,
            fromWormholeFormat(getPeer(recipientChain).peerAddress),
            encodedPayload,
            0, // receiverValue
            0, // paymentForExtraReceiverValue
            gasLimit,
            recipientChain,
            fromWormholeFormat(recipient),
            wormholeRelayer.getDefaultDeliveryProvider(),
            new VaaKey[](0),
            200 // instant finality messaging
        );

        return sequence;
    }

    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable onlyRelayer {
        if (getPeer(sourceChain).peerAddress != sourceAddress) {
            revert InvalidPeer(sourceChain, sourceAddress);
        }

        // VAA replay protection:
        // Note that this VAA is for the standard relaying delivery, not for the raw message emitted by the source
        //      chain Transceiver contract. The VAAs received by this entrypoint are different than the
        //      VAA received by the receiveMessage entrypoint.
        if (isVAAConsumed(deliveryHash)) {
            revert TransferAlreadyCompleted(deliveryHash);
        }
        _setVAAConsumed(deliveryHash);

        // We don't honor additional messages in this handler.
        if (additionalMessages.length > 0) {
            revert UnexpectedAdditionalMessages();
        }

        _parseAndMint(payload);
    }

    // manual redeem just in case
    function manualRedeem(bytes memory encodedMessage) external {
        // verify VAA
        bytes memory payload = _verifyMessage(encodedMessage);
        _parseAndMint(payload);
    }

    function _parseAndMint(bytes memory payload) internal {
        // parse and validate message
        BurnMintMessage memory m = _parseBurnMintMessage(payload);
        address recipient = fromWormholeFormat(m.to);

        // verify that the destination chain is valid
        if (m.toChain != chainId) {
            revert InvalidTargetChain(m.toChain, chainId);
        }

        // mint tokens to recipient
        IMintingToken(token).mint(recipient, m.amount);
    }
}
