// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { AddressResolver } from "../common/AddressResolver.sol";
import { EssentialContract } from "../common/EssentialContract.sol";
import { ICrossChainSync } from "../common/ICrossChainSync.sol";
import { LibEthDepositing } from "./libs/LibEthDepositing.sol";
import { LibProposing } from "./libs/LibProposing.sol";
import { LibProving } from "./libs/LibProving.sol";
import { LibUtils } from "./libs/LibUtils.sol";
import { LibVerifying } from "./libs/LibVerifying.sol";
import { TaikoErrors } from "./TaikoErrors.sol";
import { TaikoData } from "./TaikoData.sol";
import { TaikoEvents } from "./TaikoEvents.sol";

/// @title TaikoL1Base
/// @notice This contract serves as the "base layer contract" of the Taiko
/// protocol, providing functionalities for proposing, proving, and verifying
/// blocks. The term "base layer contract" means that although this is usually
/// deployed on L1, it can also be deployed on L2s to create L3s ("inception
/// layers"). The contract also handles the deposit and withdrawal of Taiko
/// tokens and Ether.
abstract contract TaikoL1Base is
    EssentialContract,
    ICrossChainSync,
    TaikoEvents,
    TaikoErrors
{
    using LibUtils for TaikoData.State;

    TaikoData.State public state;
    uint256[100] private __gap;

    /// @dev Fallback function to receive Ether and deposit to to Layer 2.
    receive() external payable {
        depositEtherToL2(address(0));
    }

    /// @notice Initializes the rollup.
    /// @param _addressManager The {AddressManager} address.
    /// @param _genesisBlockHash The block hash of the genesis block.
    function init(
        address _addressManager,
        bytes32 _genesisBlockHash
    )
        external
        initializer
    {
        EssentialContract._init(_addressManager);
        LibVerifying.init({
            state: state,
            config: getConfig(),
            genesisBlockHash: _genesisBlockHash
        });
    }

    /// @notice Proposes a Taiko L2 block.
    /// @param input An abi-encoded BlockMetadataInput that the actual L2 block
    /// header must satisfy.
    /// @param txList A list of transactions in this block, encoded with RLP.
    /// Note, in the corresponding L2 block an "anchor transaction" will be the
    /// first transaction in the block. If there are `n` transactions in the
    /// `txList`, then there will be up to `n + 1` transactions in the L2 block.
    /// @return meta The metadata of the proposed L2 block.
    function proposeBlock(
        bytes calldata input,
        bytes calldata txList
    )
        external
        payable
        nonReentrant
        returns (TaikoData.BlockMetadata memory meta)
    {
        TaikoData.Config memory config = getConfig();
        meta = LibProposing.proposeBlock({
            state: state,
            config: config,
            resolver: AddressResolver(this),
            input: abi.decode(input, (TaikoData.BlockMetadataInput)),
            txList: txList
        });
        if (config.blockMaxVerificationsPerTx > 0) {
            LibVerifying.verifyBlocks({
                state: state,
                config: config,
                resolver: AddressResolver(this),
                maxBlocks: config.blockMaxVerificationsPerTx
            });
        }
    }

    /// @notice Proves a block with a zero-knowledge proof.
    /// @param blockId The index of the block to prove. This is also used to
    /// select the right implementation version.
    /// @param input An abi-encoded {TaikoData.BlockEvidence} object.
    function proveBlock(
        uint64 blockId,
        bytes calldata input
    )
        external
        nonReentrant
    {
        TaikoData.Config memory config = getConfig();
        LibProving.proveBlock({
            state: state,
            config: config,
            resolver: AddressResolver(this),
            blockId: blockId,
            evidence: abi.decode(input, (TaikoData.BlockEvidence))
        });
        if (config.blockMaxVerificationsPerTx > 0) {
            LibVerifying.verifyBlocks({
                state: state,
                config: config,
                resolver: AddressResolver(this),
                maxBlocks: config.blockMaxVerificationsPerTx
            });
        }
    }

    /// @notice Verifies up to N blocks.
    /// @param maxBlocks Max number of blocks to verify.
    function verifyBlocks(uint64 maxBlocks) external nonReentrant {
        if (maxBlocks == 0) revert L1_INVALID_PARAM();
        LibVerifying.verifyBlocks({
            state: state,
            config: getConfig(),
            resolver: AddressResolver(this),
            maxBlocks: maxBlocks
        });
    }

    /// @notice Deposits Ether to Layer 2.
    /// @param recipient Address of the recipient for the deposited Ether on
    /// Layer 2.
    function depositEtherToL2(address recipient) public payable {
        LibEthDepositing.depositEtherToL2({
            state: state,
            config: getConfig(),
            resolver: AddressResolver(this),
            recipient: recipient
        });
    }

    /// @notice Checks if Ether deposit is allowed for Layer 2.
    /// @param amount Amount of Ether to be deposited.
    /// @return true if Ether deposit is allowed, false otherwise.
    function canDepositEthToL2(uint256 amount) public view returns (bool) {
        return LibEthDepositing.canDepositEthToL2({
            state: state,
            config: getConfig(),
            amount: amount
        });
    }

    /// @notice Gets the details of a block.
    /// @param blockId Index of the block.
    /// @return _metaHash Metadata hash of the block.
    /// @return _proposedAt Timestamp when the block was proposed.
    /// @return _prover Address of the assigned prover for the block.
    /// @return _nextForkChoiceId Next fork choice ID of the block.
    /// @return _verifiedForkChoiceId Verified fork choice ID of the block.
    function getBlock(uint64 blockId)
        public
        view
        returns (
            bytes32 _metaHash,
            uint64 _proposedAt,
            address _prover,
            uint16 _nextForkChoiceId,
            uint16 _verifiedForkChoiceId
        )
    {
        TaikoData.Block storage blk = LibProposing.getBlock({
            state: state,
            config: getConfig(),
            blockId: blockId
        });

        _metaHash = blk.metaHash;
        _proposedAt = blk.proposedAt;
        _prover = blk.prover;
        _nextForkChoiceId = blk.nextForkChoiceId;
        _verifiedForkChoiceId = blk.verifiedForkChoiceId;
    }

    /// @notice Gets the fork choice for a specific block.
    /// @param blockId Index of the block.
    /// @param parentHash Parent hash of the block.
    /// @param parentGasUsed Gas used by the parent block.
    /// @return ForkChoice data of the block.
    function getForkChoice(
        uint64 blockId,
        bytes32 parentHash,
        uint32 parentGasUsed
    )
        public
        view
        returns (TaikoData.ForkChoice memory)
    {
        return LibProving.getForkChoice({
            state: state,
            config: getConfig(),
            blockId: blockId,
            parentHash: parentHash,
            parentGasUsed: parentGasUsed
        });
    }

    /// @inheritdoc ICrossChainSync
    function getCrossChainBlockHash(uint64 blockId)
        public
        view
        override
        returns (bytes32)
    {
        (bool found, TaikoData.Block storage blk) = LibUtils.getL2ChainData({
            state: state,
            config: getConfig(),
            blockId: blockId
        });
        return found
            ? blk.forkChoices[blk.verifiedForkChoiceId].blockHash
            : bytes32(0);
    }

    /// @inheritdoc ICrossChainSync
    function getCrossChainSignalRoot(uint64 blockId)
        public
        view
        override
        returns (bytes32)
    {
        (bool found, TaikoData.Block storage blk) = LibUtils.getL2ChainData({
            state: state,
            config: getConfig(),
            blockId: blockId
        });

        return found
            ? blk.forkChoices[blk.verifiedForkChoiceId].signalRoot
            : bytes32(0);
    }

    /// @notice Gets the state variables of the TaikoL1 contract.
    /// @return StateVariables struct containing state variables.
    function getStateVariables()
        public
        view
        returns (TaikoData.StateVariables memory)
    {
        return state.getStateVariables();
    }

    /// @notice Gets the name of the proof verifier by ID.
    /// @param id ID of the verifier.
    /// @return Verifier name.
    function getVerifierName(uint16 id) public pure returns (bytes32) {
        return LibUtils.getVerifierName(id);
    }

    /// @notice Gets the configuration of the TaikoL1 contract.
    /// @return Config struct containing configuration parameters.
    function getConfig()
        public
        pure
        virtual
        returns (TaikoData.Config memory);
}