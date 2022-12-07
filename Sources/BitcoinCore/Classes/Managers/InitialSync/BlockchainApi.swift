import RxSwift
import ObjectMapper
import Alamofire
import HsToolKit

public class BlockchainApi {
    private let baseUrl: String
    private let authKey: String
    private let networkManager: NetworkManager
    private let jwtService: JwtService
    
    public init(baseUrl: String, authKey: String, logger: Logger? = nil) {
        self.baseUrl = baseUrl
        self.authKey = authKey
        networkManager = NetworkManager(logger: logger)
        jwtService = JwtService()
    }
    
    private func transactionsSingle(addresses: [String], jwt: String) -> Single<[SyncTransactionItem]> {
        let parameters: Parameters = [
            "addresses": addresses
        ]
        
        let path = "/bitcoin/testnet/getTransactions"
        let headers: HTTPHeaders = ["Authorization": jwt, "Content-Type": "application/json"]
        
        let request = networkManager.session.request(baseUrl + path, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
        return networkManager.single(request: request)
    }
    
}

extension BlockchainApi: ISyncTransactionApi {
    
    public func getTransactions(addresses: [String]) -> Single<[SyncTransactionItem]> {
        jwtService
            .jwtSingle(baseUrl: baseUrl, authKey: authKey)
            .flatMap { [unowned self] response in
                let jwt = response.data.token
                return transactionsSingle(addresses: addresses, jwt: jwt)
            }
    }
    
}
