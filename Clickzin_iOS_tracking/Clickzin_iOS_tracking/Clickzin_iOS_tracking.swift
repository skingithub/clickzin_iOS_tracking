import Foundation
import CryptoKit
import UIKit
import SystemConfiguration.CaptiveNetwork

// MARK: - Tracking Error
public enum TrackingError: LocalizedError {
    case apiKeyNotSet
    case trackingNotInitialized
    case invalidResponse
    case noMatchingReferrer
    
    public var errorDescription: String? {
        switch self {
        case .apiKeyNotSet: return "[Clickzin] API key not set"
        case .trackingNotInitialized: return "[Clickzin] Call startTracking first"
        case .invalidResponse: return "[Clickzin] Invalid response received"
        case .noMatchingReferrer: return "[Clickzin] No matching referrer found"
        }
    }
}

// MARK: - Constants
fileprivate enum Constants {
    static let TRACKING_BASE_URL = "https://tracking.kalpssoft.com"
    static let TRACKING_IOS_POSTBACK_URL = "\(TRACKING_BASE_URL)/postback/ios"
    static let TEST_UID = "testing"
    static let TEST_SOURCE = "clickzin"
    static let LOG_PREFIX = "[Clickzin]"
}

// MARK: - HTTP Method Type
public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

// MARK: - Configuration
public struct ClickzinConfiguration {
    let apiKey: String
    let isTestMode: Bool
    
    public init(apiKey: String, isTestMode: Bool = false) {
        self.apiKey = apiKey
        self.isTestMode = isTestMode
    }
}

/// Main class for handling Clickzin tracking functionality
public final class ClickzinTracking {
  
    // MARK: - Properties
    private static let queue = DispatchQueue(label: "com.clickzin.tracking", qos: .utility)
    private static let lock = NSLock()
    
    private static var _isTrackingDone = false
    private static var isTrackingDone: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isTrackingDone
        }
        set {
            lock.lock()
            _isTrackingDone = newValue
            lock.unlock()
        }
    }
    
    private static var apiKey: String = ""
    private static var uid: String?
    private static var source: String?
    
    // MARK: - Logging
    public static var isDebugLoggingEnabled = true
    
    private static var configuration: ClickzinConfiguration?
    
    // MARK: - Public Methods
    public static func configure(_ config: ClickzinConfiguration) {
        configuration = config
        apiKey = config.apiKey
    }
    
    public static func startTracking(
        callback: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let config = configuration else {
            callback?(.failure(TrackingError.apiKeyNotSet))
            return
        }
        
        if isTrackingDone {
            log("Already tracked")
            callback?(.success(()))
            return
        }
        
        if config.isTestMode {
            setupTestMode()
            sendTracking(callback: callback)
            return
        }
        
        setupProductionMode()
        fetchIPAndInitiateTracking(callback: callback)
    }
    
    public static func trackEvent(
        _ eventId: String,
        callback: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard isTrackingDone, let uid = uid else {
            callback?(.failure(TrackingError.trackingNotInitialized))
            return
        }
        
        let url = "\(Constants.TRACKING_IOS_POSTBACK_URL)?uid=\(uid)&event=\(eventId)"
        
        Utils.sendAPIRequest(urlString: url, parameters: [:]) { response in
            if let error = response.error {
                callback?(.failure(error))
                return
            }
            
            guard response.data != nil else {
                callback?(.failure(NetworkError.noData))
                return
            }
            
            log("Tracked event \(eventId)")
            log("Response \(String(data: response.data!, encoding: .utf8) ?? "Empty"))")
            callback?(.success(()))
        }
    }
    
    // MARK: - Private Methods
    private static func setupTestMode() {
        uid = Constants.TEST_UID
        source = Constants.TEST_SOURCE
    }
    
    private static func setupProductionMode() {
        uid = UIDevice.current.identifierForVendor?.uuidString
        source = Utils.appName()
    }
    
    private static func fetchIPAndInitiateTracking(
        callback: ((Result<Void, Error>) -> Void)?
    ) {
        
        let ipaddresses = Utils.getAllIPAddresses()
        let ua = UIDevice.current.systemName + " " + UIDevice.current.systemVersion
        
        var ip = "N"
        if let wifiIP = ipaddresses["en0"] {
            log("Wi-Fi IP: \(wifiIP)")
            ip = wifiIP
        }
        if let cellularIP = ipaddresses["pdp_ip0"] {
            log("Cellular IP: \(cellularIP)")
            ip = ip + cellularIP
        }
        
        let hash = generateHash(ip: ip, userAgent: ua)
        initiateTracking(with: hash, callback: callback)
    }
    
    private static func extractIPAndUA(from data: Data?) throws -> (String, String) {
        guard let data = data,
              let ipJson = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let ip = ipJson["ip"],
              let ua = UIDevice.current.systemName + " " + UIDevice.current.systemVersion as String?
        else {
            throw TrackingError.invalidResponse
        }
        return (ip, ua)
    }
    
    private static func initiateTracking(
        with hash: String,
        callback: ((Result<Void, Error>) -> Void)?
    ) {
        let trackingUrl = "\(Constants.TRACKING_IOS_POSTBACK_URL)?ip_user_agent_hash=\(hash)"
        
        Utils.sendAPIRequest(urlString: trackingUrl, parameters: [:]) { response in
            if let error = response.error {
                log("Error \(error)")
                callback?(.failure(error))
                return
            }
            do {
                try processTrackingResponse(response.data)
                callback?(.success(()))
            } catch {
                callback?(.failure(error))
            }
        }
    }
    
    private static func processTrackingResponse(_ data: Data?) throws {

        guard let data = data,
              let response = String(data: data, encoding: .utf8),
              response.contains("true")  else {
            throw TrackingError.noMatchingReferrer
        }
        log("Response \(response)")
    }
    

    private static func sendTracking(
        callback: ((Result<Void, Error>) -> Void)?
    ) {
        guard let uid = uid else { return }
        
        let url = "\(Constants.TRACKING_IOS_POSTBACK_URL)?uid=\(uid)"
        
        Utils.sendAPIRequest(urlString: url, parameters: [:]) { response in
            if let error = response.error {
                callback?(.failure(error))
                return
            }
            
            guard response.data != nil else {
                callback?(.failure(NetworkError.noData))
                return
            }
            
            isTrackingDone = true
            log("Tracked install for \(uid)")
            callback?(.success(()))
        }
    }
    
    private static func generateHash(ip: String, userAgent: String) -> String {
        let input = ip + userAgent
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private static func log(_ message: String, level: LogLevel = .info) {
        guard isDebugLoggingEnabled else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("\(Constants.LOG_PREFIX) [\(timestamp)] [\(level.rawValue)] \(message)")
    }
    
    private enum LogLevel: String {
        case info = "INFO"
        case error = "ERROR"
        case debug = "DEBUG"
    }
    
    // MARK: - Utilities
    public class Utils {
        // MARK: - Network
        public static func sendAPIRequest(
            urlString: String,
            parameters: [String: Any],
            method: HTTPMethod = .get,
            headers: [String: String]? = nil,
            timeoutInterval: TimeInterval = 30,
            completion: @escaping (APIResponse) -> Void
        ) {
            // Validate URL
            guard let url = URL(string: urlString) else {
                completion(APIResponse(data: nil, error: NetworkError.invalidURL))
                return
            }

            // Setup request
            var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
            request.httpMethod = method.rawValue
            
            // Add default headers
            var defaultHeaders = [
                "Accept": "application/json",
                "User-Agent": userAgent
            ]
            
            // Merge with custom headers
            if let customHeaders = headers {
                defaultHeaders.merge(customHeaders) { _, new in new }
            }
            
            // Apply headers
            defaultHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            
            // Add parameters for GET requests as query items
            if method == .get && !parameters.isEmpty {
                guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                    completion(APIResponse(data: nil, error: NetworkError.invalidParameters))
                    return
                }
                
                components.queryItems = parameters.map {
                    URLQueryItem(name: $0.key, value: String(describing: $0.value))
                }
                
                guard let finalUrl = components.url else {
                    completion(APIResponse(data: nil, error: NetworkError.invalidParameters))
                    return
                }
                
                request.url = finalUrl
            }
            
            // Add parameters for POST requests in body
            if method == .post && !parameters.isEmpty {
                do {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
                } catch {
                    completion(APIResponse(data: nil, error: error))
                    return
                }
            }

            // Perform request
            URLSession.shared.dataTask(with: request) { data, response, error in
                data != nil ? log("Data \(String(data: data!, encoding: .utf8) ?? "Empty")") : log("Data Empty")
                log("Error \(error)")
                log("Response \(response)")
                completion(APIResponse(data: data, error: error))
            }.resume()
        }
        
        // MARK: - App Info
        fileprivate static func appName() -> String {
            Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ??
            Bundle.main.infoDictionary?["CFBundleName"] as? String ??
            "No Name Found"
        }
        
        // Add computed property for user agent
        private static var userAgent: String {
            let device = UIDevice.current
            return "\(device.systemName)/\(device.systemVersion) (\(device.model))"
        }
        

        fileprivate static func getAllIPAddresses() -> [String: String] {
            var addresses: [String: String] = [:]
            var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil

            guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return addresses }

            for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
                let interface = ptr.pointee
                let addrFamily = interface.ifa_addr.pointee.sa_family

                if addrFamily == UInt8(AF_INET) { // IPv4 only, or add || addrFamily == UInt8(AF_INET6) for IPv6
                    let name = String(cString: interface.ifa_name)
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                                socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                socklen_t(0),
                                NI_NUMERICHOST)

                    let ip = String(cString: hostname)
                    addresses[name] = ip
                }
            }

            freeifaddrs(ifaddr)
            return addresses
        }



    }
}

// MARK: - Network Response
public struct APIResponse {
    let data: Data?
    let error: Error?
}

// MARK: - Network Error
public enum NetworkError: LocalizedError {
    case invalidURL
    case invalidParameters
    case noData
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The URL provided is invalid"
        case .invalidParameters: return "Invalid parameters for request"
        case .noData: return "No data received from the server"
        }
    }
}

