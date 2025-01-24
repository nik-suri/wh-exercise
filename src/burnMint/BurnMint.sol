// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "wormhole-solidity-sdk/libraries/BytesParsing.sol";
import "wormhole-solidity-sdk/WormholeRelayerSDK.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "src/token/IMintingToken.sol";
import "src/burnMint/BurnMintState.sol";

// integrates with wormhole for burn/mint token transfers
contract BurnMint is BurnMintState, IWormholeReceiver {
    using SafeERC20 for IERC20;
    using BytesParsing for bytes;

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
        // query own token balance before transfer
        uint256 balanceBefore = _getTokenBalanceOf(token, address(this));

        // transfer tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // query own token balance after transfer
        uint256 balanceAfter = _getTokenBalanceOf(token, address(this));

        // correct amount for potential transfer fees
        amount = balanceAfter - balanceBefore;

        // burn tokens
        // NOTE: We don't account for burn fees in this code path.
        // We verify that the user's change in balance is equal to the amount that's burned.
        // Accounting for burn fees can be non-trivial, since there
        // is no standard way to account for the fee if the fee amount
        // is taken out of the burn amount.
        // For example, if there's a fee of 1 which is taken out of the
        // amount, then burning 20 tokens would result in a transfer of only 19 tokens.
        // However, the difference in the user's balance would only show 20.
        // Since there is no standard way to query for burn fee amounts with burnable tokens,
        // and NTT would be used on a per-token basis, implementing this functionality
        // is left to integrating projects who may need to account for burn fees on their tokens.
        ERC20Burnable(token).burn(amount);

        // tokens held by the contract after the operation should be the same as before
        uint256 balanceAfterBurn = _getTokenBalanceOf(token, address(this));
        if (balanceBefore != balanceAfterBurn) {
            revert BurnAmountDifferentThanBalanceDiff(balanceBefore, balanceAfterBurn);
        }

        // format message
        // construct the NttManagerMessage payload
        bytes memory encodedPayload = _encodeBurnMintMessage(
            BurnMintMessage(toWormholeFormat(msg.sender), amount, toWormholeFormat(token), recipient, recipientChain)
        );

        // send via wormhole standard relaying
        // uint64 sequence = wormholeRelayer.sendPayloadToEvm{value: cost}(
        //     recipientChain,
        //     fromWormholeFormat(getPeer(recipientChain).peerAddress),
        //     encodedPayload,
        //     0, // receiverValue
        //     gasLimit
        // );
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

    function _getTokenBalanceOf(address tokenAddr, address accountAddr) internal view returns (uint256) {
        (bool success, bytes memory queriedBalance) =
            tokenAddr.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, accountAddr));

        if (!success) {
            revert StaticcallFailed();
        }

        return abi.decode(queriedBalance, (uint256));
    }

    /// @dev Message emitted and received by the nttManager contract.
    ///      The wire format is as follows:
    ///      - sender - 32 bytes
    ///      - amount - 32 bytes
    ///      - sourceToken - 32 bytes
    ///      - to - 32 bytes
    ///      - toChain - 2 bytes
    struct BurnMintMessage {
        /// @notice original message sender address.
        bytes32 sender;
        /// @notice Amount being transferred (big-endian u64 and u8 for decimals)
        uint256 amount;
        /// @notice Source chain token address.
        bytes32 sourceToken;
        /// @notice Address of the recipient.
        bytes32 to;
        /// @notice Chain ID of the recipient
        uint16 toChain;
    }

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
