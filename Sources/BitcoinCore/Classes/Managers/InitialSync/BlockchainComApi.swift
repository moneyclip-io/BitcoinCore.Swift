import RxSwift
import ObjectMapper
import Alamofire
import HsToolKit

public class BlockchainComApi {
    private static let paginationLimit = 100
    private static let addressesLimit = 50

    private let url: String
    private let hsUrl: String
    private let jwtUrl: String
    private let authKey: String
    private let networkManager: NetworkManager
    private let jwtService: JwtService

    private static var serialSchedulers = [String: SerialDispatchQueueScheduler]()
    private let serialScheduler: SerialDispatchQueueScheduler

    public init(url: String, hsUrl: String, jwtUrl: String, authKey: String, logger: Logger? = nil) {
        self.url = url
        self.hsUrl = hsUrl
        self.jwtUrl = jwtUrl
        self.authKey = authKey
        networkManager = NetworkManager(logger: logger)
        jwtService = JwtService()

        if let scheduler = Self.serialSchedulers[url] {
            serialScheduler = scheduler
        } else {
            serialScheduler = SerialDispatchQueueScheduler(qos: .utility)
            Self.serialSchedulers[url] = serialScheduler
        }
    }

    private func addressesSingle(addresses: [String], offset: Int = 0) -> Single<AddressesResponse> {
        let parameters: Parameters = [
            "active": addresses.joined(separator: "|"),
            "n": Self.paginationLimit,
            "offset": offset
        ]

        let request = networkManager.session.request("\(url)/multiaddr", method: .get, parameters: parameters)
        return networkManager.single(request: request, sync: true, postDelay: 0.5)
    }

    private func blocksSingle(heights: [Int]) -> Single<[BlockResponse]> {
        jwtService
            .jwtSingle(baseUrl: jwtUrl, authKey: authKey)
            .flatMap { [unowned self] response in
                let jwt = response.data.token
                let headers: HTTPHeaders = ["Authorization": jwt, "Content-Type": "application/json"]
                
                let parameters: Parameters = [
                    "numbers": heights.map { String($0) }.joined(separator: ",")
                ]
                
                let request = networkManager.session.request("\(hsUrl)/hashes", method: .get, parameters: parameters, headers: headers)
                return networkManager.single(request: request)
            }
    }

    private func itemsSingle(transactionResponses: [TransactionResponse]) -> Single<[SyncTransactionItem]> {
        let blockHeights = Array(Set(transactionResponses.compactMap { $0.blockHeight }))

        guard !blockHeights.isEmpty else {
            return Single.just([])
        }

        return blocksSingle(heights: blockHeights)
                .map { blocks in
                    transactionResponses.compactMap { response in
                        guard let block = blocks.first(where: { $0.height == response.blockHeight }) else {
                            return nil
                        }

                        return SyncTransactionItem(
                                hash: block.hash,
                                height: block.height,
                                txOutputs: response.outputs.map {
                                    SyncTransactionOutputItem(script: $0.script, address: $0.address)
                                }
                        )
                    }
                }
    }

    private func itemsSingle(addresses: [String], offset: Int) -> Single<[SyncTransactionItem]> {
        addressesSingle(addresses: addresses, offset: offset)
                .subscribeOn(serialScheduler)
                .flatMap { [unowned self] response in
                    itemsSingle(transactionResponses: response.transactions)
                }
    }

    private func itemsSingle(addressChunk: [String], offset: Int = 0) -> Single<[SyncTransactionItem]> {
        itemsSingle(addresses: addressChunk, offset: offset)
                .flatMap { [unowned self] chunkItems in
                    if chunkItems.count < Self.paginationLimit {
                        return Single.just(chunkItems)
                    }

                    return itemsSingle(addressChunk: addressChunk, offset: offset + Self.paginationLimit).map { items in
                        chunkItems + items
                    }
                }
    }

    public func itemsSingle(allAddresses: [String], index: Int = 0) -> Single<[SyncTransactionItem]> {
        let startIndex = index * Self.addressesLimit

        guard startIndex <= allAddresses.count else {
            return Single.just([])
        }

        let endIndex = min(allAddresses.count, (index + 1) * Self.addressesLimit)
        let chunk = Array(allAddresses[startIndex..<endIndex])

        return itemsSingle(addressChunk: chunk).flatMap { [unowned self] items in
            itemsSingle(allAddresses: allAddresses, index: index + 1).map { allItems in
                allItems + items
            }
        }
    }

}

extension BlockchainComApi: ISyncTransactionApi {

    public func getTransactions(addresses: [String]) -> Single<[SyncTransactionItem]> {
        itemsSingle(allAddresses: addresses)
    }

}

extension BlockchainComApi {

    struct AddressesResponse: ImmutableMappable {
        let transactions: [TransactionResponse]

        init(map: Map) throws {
            transactions = try map.value("txs")
        }
    }

    struct TransactionResponse: ImmutableMappable {
        let blockHeight: Int?
        let outputs: [TransactionOutputResponse]

        init(map: Map) throws {
            blockHeight = try? map.value("block_height")
            outputs = try map.value("out")
        }
    }

    struct TransactionOutputResponse: ImmutableMappable {
        let script: String
        let address: String?

        init(map: Map) throws {
            script = try map.value("script")
            address = try? map.value("addr")
        }
    }

    struct BlockResponse: ImmutableMappable {
        let height: Int
        let hash: String

        init(map: Map) throws {
            height = try map.value("number")
            hash = try map.value("hash")
        }
    }

}
