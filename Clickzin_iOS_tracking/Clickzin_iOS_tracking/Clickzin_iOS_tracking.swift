
import Foundation
import UIKit
import CryptoKit

public class ClickzinTracking {
    
    private static var apiKey: String = ""
    private static var isTrackingDone = false
    private static var uid: String?
    private static var source: String?
    
    public static func setApiKey(_ key: String) {
        apiKey = key
    }
    
    public static func startTracking(callback: (() -> Void)? = nil, isTestMode: Bool = false) {
        if isTrackingDone {
            print("[Clickzin] Already tracked")
            callback?()
            return
        }
        
        if isTestMode {
            uid = "testing"
            source = "clickzin"
            sendTracking(callback: callback)
            return
        }
        else{
            uid = UIDevice.current.identifierForVendor?.uuidString
        }
        
        let ipUrl = URL(string: "https://api64.ipify.org?format=json")!
        URLSession.shared.dataTask(with: ipUrl) { data, _, error in
            guard let data = data,
                  let ipJson = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let ip = ipJson["ip"],
                  let ua = UIDevice.current.systemName + " " + UIDevice.current.systemVersion as String? else {
                print("[Clickzin] Unable to get IP or UA")
                return
            }
            
            let hash = generateHash(ip: ip, userAgent: ua)
            let url = URL(string: "https://tracking.kalpssoft.com/postback/ios?ip_user_agent_hash=\(hash)")!
            
            URLSession.shared.dataTask(with: url) { data, _, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let fetchedUid = json["utm_uid"] as? String,
                      let fetchedSource = json["utm_source"] as? String,
                      fetchedSource.lowercased().contains("clickzin") else {
                    print("[Clickzin] No matching referrer found")
                    return
                }
                
                uid = fetchedUid
                source = fetchedSource
                sendTracking(callback: callback)
            }.resume()
        }.resume()
    }
        
        
        private static func sendTracking(callback: (() -> Void)?) {
            guard let uid = uid else { return }

            let url = URL(string: "https://tracking.kalpssoft.com/postback?uid=\(uid)")!
            URLSession.shared.dataTask(with: url) { _, _, _ in
                isTrackingDone = true
                print("[Clickzin] Tracked install for \(uid)")
                callback?()
            }.resume()
        }

        public static func trackEvent(_ eventId: String, callback: (() -> Void)? = nil) {
            guard isTrackingDone, let uid = uid else {
                print("[Clickzin] Call startTracking first.")
                return
            }

            let url = URL(string: "https://tracking.kalpssoft.com/postback?uid=\(uid)&event=\(eventId)")!
            URLSession.shared.dataTask(with: url) { _, _, _ in
                print("[Clickzin] Tracked event \(eventId)")
                callback?()
            }.resume()
        }

        private static func generateHash(ip: String, userAgent: String) -> String {
            let input = ip + userAgent
            let inputData = Data(input.utf8)
            let hashed = SHA256.hash(data: inputData)
            return hashed.compactMap { String(format: "%02x", $0) }.joined()
        }

    }
