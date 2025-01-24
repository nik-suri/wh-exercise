// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IBurnMint {
    function token() external returns (address);
    function quotePrice(uint16 recipientChain) external view returns (uint256 cost);
    function transfer(uint256 amount, uint16 recipientChain, bytes32 recipient) external payable returns (uint64);
    function setPeer(uint16 peerChainId, bytes32 peerContract) external;
    function getPeer(uint16 chainId_) external view returns (Peer memory);
    function manualRedeem(bytes memory encodedMessage) external;

    struct _Sequence {
        uint64 num;
    }

    /// @dev The peer on another chain.
    struct Peer {
        bytes32 peerAddress;
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

    error ZeroAmount();
    error InvalidRecipient();
    error DeliveryPaymentTooLow(uint256 requiredPayment, uint256 providedPayment);
    error BurnAmountDifferentThanBalanceDiff(uint256 burnAmount, uint256 balanceDiff);
    error StaticcallFailed();
    error InvalidPeerChainIdZero();
    error InvalidPeerZeroAddress();
    error InvalidPeerSameChainId();
    error InvalidTargetChain(uint16 targetChain, uint16 thisChain);
    error InvalidVaa(string reason);
    error TransferAlreadyCompleted(bytes32 vaaHash);
    error InvalidPeer(uint16 sourceChain, bytes32 sourceAddress);
    error UnauthorizedAccount(address sender);
    error CallerNotRelayer(address sender);
    error UnexpectedAdditionalMessages();
}
