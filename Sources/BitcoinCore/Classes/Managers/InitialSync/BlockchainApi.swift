import RxSwift
import ObjectMapper
import Alamofire
import HsToolKit

public class BlockchainApi {
    private let url: String
    private let authKey: String
    private let networkManager: NetworkManager
    
    public init(url: String, authKey: String, logger: Logger? = nil) {
        self.url = url
        self.authKey = authKey
        networkManager = NetworkManager(logger: logger)
    }
    
    private func jwtSingle() -> Single<JWTResponse> {
        let path = "/authentication/requestJWT"
        let headers: HTTPHeaders = ["Authorization": authKey, "Accept": "application/json"]
        
        let request = networkManager.session.request(url + path, method: .get, encoding: JSONEncoding.default, headers: headers)
        return networkManager.single(request: request)
    }
    
    private func transactionsSingle(addresses: [String], jwt: String) -> Single<[SyncTransactionItem]> {
        let parameters: Parameters = [
            "addresses": addresses
        ]
        
        let path = "/bitcoin/testnet/getTransactions"
        let headers: HTTPHeaders = ["Authorization": jwt, "Content-Type": "application/json"]
        
        let request = networkManager.session.request(url + path, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
        return networkManager.single(request: request)
    }
    
}

extension BlockchainApi: ISyncTransactionApi {
    
    public func getTransactions(addresses: [String]) -> Single<[SyncTransactionItem]> {
        jwtSingle()
            .flatMap { [unowned self] response in
                let jwt = response.data.token
                return transactionsSingle(addresses: addresses, jwt: jwt)
            }
    }
    
}

extension BlockchainApi {
    
    struct JWTResponse: ImmutableMappable {
        let data: JWTData
        
        init(map: Map) throws {
            data = try map.value("data")
        }
    }
    
    struct JWTData: ImmutableMappable {
        let token: String
        
        init(map: Map) throws {
            token = try map.value("token")
        }
    }
    
}
