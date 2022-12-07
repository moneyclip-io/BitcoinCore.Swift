import RxSwift
import ObjectMapper
import Alamofire
import HsToolKit

class JwtService {
    private let networkManager = NetworkManager()
    
    func jwtSingle(baseUrl: String, authKey: String) -> Single<Response> {
        let path = "/authentication/requestJWT"
        let headers: HTTPHeaders = ["Authorization": authKey, "Accept": "application/json"]
        
        let request = networkManager.session.request(baseUrl + path, method: .get, encoding: JSONEncoding.default, headers: headers)
        return networkManager.single(request: request)
    }
    
}

extension JwtService {
    
    struct Response: ImmutableMappable {
        let data: Data
        
        init(map: Map) throws {
            data = try map.value("data")
        }
    }
    
    struct Data: ImmutableMappable {
        let token: String
        
        init(map: Map) throws {
            token = try map.value("token")
        }
    }
    
}
