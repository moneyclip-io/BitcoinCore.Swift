import RxSwift
import ObjectMapper
import Alamofire
import HsToolKit

public class BCoinApi {
    private let url: String
    private let authKey: String
    private let networkManager: NetworkManager
    private let jwtService: JwtService

    public init(url: String, authKey: String, logger: Logger? = nil) {
        self.url = url
        self.authKey = authKey
        networkManager = NetworkManager(logger: logger)
        jwtService = JwtService()
    }

}

extension BCoinApi: ISyncTransactionApi {

    public func getTransactions(addresses: [String]) -> Single<[SyncTransactionItem]> {
        jwtService
            .jwtSingle(baseUrl: url, authKey: authKey)
            .flatMap { [unowned self] response in
                let jwt = response.data.token
                let parameters: Parameters = [
                    "addresses": addresses
                ]
                
                let path = "/bitcoin/testnet/getTransactions"
                let headers: HTTPHeaders = ["Authorization": jwt, "Content-Type": "application/json"]
                
                let request = networkManager.session.request(url + path, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                return networkManager.single(request: request)
            }
    }

}
