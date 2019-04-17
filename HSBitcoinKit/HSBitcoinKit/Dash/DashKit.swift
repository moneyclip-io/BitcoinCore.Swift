import Foundation
import HSHDWalletKit
import BigInt
import HSCryptoKit
import RxSwift

public class DashKit: AbstractKit {
    private static let heightInterval = 24                                      // Blocks count in window for calculating difficulty
    private static let targetSpacing = 150                                      // Time to mining one block ( 2.5 min. Dash )
    private static let maxTargetBits = 0x1e0fffff                               // Initially and max. target difficulty for blocks ( Dash )

    public enum NetworkType { case mainNet, testNet }

    public weak var delegate: BitcoinCoreDelegate? {
        didSet {
            guard let delegate = delegate else {
                return
            }
            bitcoinCore.add(delegate: delegate)
        }
    }

    private let storage: IDashStorage

    private var masternodeSyncer: MasternodeListSyncer?

    public init(withWords words: [String], walletId: String, networkType: NetworkType = .mainNet, minLogLevel: Logger.Level = .verbose) throws {
        let network: INetwork
        switch networkType {
            case .mainNet: network = DashMainNet()
            case .testNet: network = DashTestNet()
        }

        let databaseFileName = "\(walletId)-dash-\(networkType)"

        let storage = DashGrdbStorage(databaseFileName: databaseFileName)
        self.storage = storage

        let paymentAddressParser = PaymentAddressParser(validScheme: "dash", removeScheme: true)
        let addressSelector = BitcoinAddressSelector()
        let apiFeeRateResource = "DASH"

        let bitcoinCore = try BitcoinCoreBuilder()
                .set(network: network)
                .set(words: words)
                .set(paymentAddressParser: paymentAddressParser)
                .set(addressSelector: addressSelector)
                .set(feeRateApiResource: apiFeeRateResource)
                .set(walletId: walletId)
                .set(peerSize: 4)
                .set(storage: storage)
                .set(newWallet: true)
                .build()

        super.init(bitcoinCore: bitcoinCore, network: network)

        // extending BitcoinCore

        bitcoinCore.add(delegate: self)

        let singleHasher = SingleHasher() // Use single sha256 for hash
        let hasher = MerkleRootHasher() // Use doubleSha256 for hash

        let masternodeParser = MasternodeParser(hasher: singleHasher)
        let dashMessageParsers = SetOfResponsibility()
                .append(element: TransactionLockMessageParser())
                .append(element: TransactionLockVoteMessageParser())
                .append(element: MasternodeListDiffMessageParser(masternodeParser: masternodeParser))

        let dashMessageSerializers = SetOfResponsibility()
                .append(element: GetMasternodeListDiffMessageSerializer())

        bitcoinCore.add(messageParsers: dashMessageParsers)
        bitcoinCore.add(messageSerializers: dashMessageSerializers)

        let blockHelper = BitcoinCashBlockValidatorHelper(storage: storage)
        let difficultyEncoder = DifficultyEncoder()

        let targetTimespan = DashKit.heightInterval * DashKit.targetSpacing                 // Time to mining all 24 blocks in circle
        switch networkType {
        case .mainNet:
            bitcoinCore.add(blockValidator: DarkGravityWaveValidator(encoder: difficultyEncoder, blockHelper: blockHelper, heightInterval: DashKit.heightInterval , targetTimeSpan: targetTimespan, maxTargetBits: DashKit.maxTargetBits, firstCheckpointHeight: network.checkpointBlock.height))
        case .testNet:
            bitcoinCore.add(blockValidator: DarkGravityWaveTestNetValidator(difficultyEncoder: difficultyEncoder, targetSpacing: DashKit.targetSpacing, targetTimeSpan: targetTimespan, maxTargetBits: DashKit.maxTargetBits))
            bitcoinCore.add(blockValidator: DarkGravityWaveValidator(encoder: difficultyEncoder, blockHelper: blockHelper, heightInterval: DashKit.heightInterval, targetTimeSpan: targetTimespan, maxTargetBits: DashKit.maxTargetBits, firstCheckpointHeight: network.checkpointBlock.height))
        }

        let merkleBranch = MerkleBranch(hasher: hasher)

        let masternodeSerializer = MasternodeSerializer()
        let coinbaseTransactionSerializer = CoinbaseTransactionSerializer()
        let masternodeCbTxHasher = MasternodeCbTxHasher(coinbaseTransactionSerializer: coinbaseTransactionSerializer, hasher: hasher)
        let masternodeMerkleRootCreator = MerkleRootCreator(hasher: hasher)

        let masternodeListMerkleRootCalculator = MasternodeListMerkleRootCalculator(masternodeSerializer: masternodeSerializer, masternodeHasher: hasher, masternodeMerkleRootCreator: masternodeMerkleRootCreator)
        let masternodeListManager = MasternodeListManager(storage: storage, masternodeListMerkleRootCalculator: masternodeListMerkleRootCalculator, masternodeCbTxHasher: masternodeCbTxHasher, merkleBranch: merkleBranch)
        let masternodeSyncer = MasternodeListSyncer(peerGroup: bitcoinCore.peerGroup, peerTaskFactory: PeerTaskFactory(), masternodeListManager: masternodeListManager)
        self.masternodeSyncer = masternodeSyncer

        bitcoinCore.add(peerTaskHandler: masternodeSyncer)

// --------------------------------------
        let transactionLockVoteValidator = TransactionLockVoteValidator(storage: storage, hasher: singleHasher)
        let instantSendFactory = InstantSendFactory()
        let instantTransactionManager = InstantTransactionManager(storage: storage, instantSendFactory: instantSendFactory, transactionSyncer: bitcoinCore.transactionSyncer, transactionLockVoteValidator: transactionLockVoteValidator)
        let instantSend = InstantSend(instantTransactionManager: instantTransactionManager)

        bitcoinCore.add(peerTaskHandler: instantSend)
        bitcoinCore.add(inventoryItemsHandler: instantSend)
// --------------------------------------

    }

}

extension DashKit: BitcoinCoreDelegate {

    public func lastBlockInfoUpdated(lastBlockInfo: BlockInfo) {
        if (bitcoinCore.syncState == BitcoinCore.KitState.synced) {
            if let hash = lastBlockInfo.headerHash.reversedData {
                masternodeSyncer?.sync(blockHash: hash)
            }
        }

    }

    public func kitStateUpdated(state: BitcoinCore.KitState) {
        if (state == BitcoinCore.KitState.synced) {
            if let blockInfo = bitcoinCore.lastBlockInfo, let hash = blockInfo.headerHash.reversedData {
                masternodeSyncer?.sync(blockHash: hash)
            }
        }
    }

}

public protocol DashKitDelegate: BitcoinCoreDelegate {}
