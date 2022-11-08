import Foundation
import Checkpoints
import HsExtensions

public struct Checkpoint {
    public let block: Block
    public let additionalBlocks: [Block]

    public init(block: Block, additionalBlocks: [Block]) {
        self.block = block
        self.additionalBlocks = additionalBlocks
    }
    
    public init(providedBlock: Block) {
        block = providedBlock
        additionalBlocks = []
    }

    public init(bundleName: String, network: String, blockType: CheckpointData.BlockType) throws {
        guard let blockchain = CheckpointData.Blockchain(rawValue: bundleName),
              let network = CheckpointData.Network(rawValue: network) else {
            throw ParseError.wrongParameters
        }

        let checkpointData = try CheckpointData(blockchain: blockchain, network: network, blockType: blockType)

        block = try Checkpoint.readBlock(data: checkpointData.block)
        additionalBlocks = try checkpointData.additionalBlocks.map { try Checkpoint.readBlock(data: $0) }
    }

    private static func readBlock(data: Data) throws -> Block {
        let byteStream = ByteStream(data)

        let version = Int(byteStream.read(Int32.self))
        let previousBlockHeaderHash = byteStream.read(Data.self, count: 32)
        let merkleRoot = byteStream.read(Data.self, count: 32)
        let timestamp = Int(byteStream.read(UInt32.self))
        let bits = Int(byteStream.read(UInt32.self))
        let nonce = Int(byteStream.read(UInt32.self))
        let height = Int(byteStream.read(UInt32.self))
        let headerHash = byteStream.read(Data.self, count: 32)

        let header = BlockHeader(
                version: version,
                headerHash: headerHash,
                previousBlockHeaderHash: previousBlockHeaderHash,
                merkleRoot: merkleRoot,
                timestamp: timestamp,
                bits: bits,
                nonce: nonce
        )

        return Block(withHeader: header, height: height)
    }

}

public extension Checkpoint {

    enum ParseError: Error {
        case wrongParameters
    }

}
