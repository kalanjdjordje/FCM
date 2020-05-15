import Foundation
import Vapor

public struct RegisterAPNSID {
    let appBundleId: String
    let serverKey: String?
    let sandbox: Bool
    
    public init (appBundleId: String, serverKey: String? = nil, sandbox: Bool = false) {
        self.appBundleId = appBundleId
        self.serverKey = serverKey
        self.sandbox = sandbox
    }
}

extension RegisterAPNSID {
    public static var env: RegisterAPNSID {
        guard let appBundleId = Environment.get("FCM_APP_BUNDLE_ID") else {
            fatalError("FCM: Register APNS: missing FCM_APP_BUNDLE_ID environment variable")
        }
        return .init(appBundleId: appBundleId)
    }
}

public struct APNSToFirebaseToken {
    public let registration_token, apns_token: String
    public let isRegistered: Bool
}

extension FCM {
    /// Helper method which registers your pure APNS token in Firebase Cloud Messaging
    /// and returns firebase tokens for each APNS token
    /// 
    /// Convenient way
    ///
    /// Declare `RegisterAPNSID` via extension
    /// ```swift
    /// extension RegisterAPNSID {
    ///     static var myApp: RegisterAPNSID { .init(appBundleId: "com.myapp") }
    /// }
    /// ```
    ///
    public func registerAPNS(
        _ id: RegisterAPNSID,
        tokens: String...,
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<[APNSToFirebaseToken]> {
        registerAPNS(appBundleId: id.appBundleId, serverKey: id.serverKey, sandbox: id.sandbox, tokens: tokens, on: eventLoop)
    }
    
    /// Helper method which registers your pure APNS token in Firebase Cloud Messaging
    /// and returns firebase tokens for each APNS token
    ///
    /// Convenient way
    ///
    /// Declare `RegisterAPNSID` via extension
    /// ```swift
    /// extension RegisterAPNSID {
    ///     static var myApp: RegisterAPNSID { .init(appBundleId: "com.myapp") }
    /// }
    /// ```
    ///
    public func registerAPNS(
        _ id: RegisterAPNSID,
        tokens: [String],
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<[APNSToFirebaseToken]> {
        registerAPNS(appBundleId: id.appBundleId, serverKey: id.serverKey, sandbox: id.sandbox, tokens: tokens, on: eventLoop)
    }
    
    /// Helper method which registers your pure APNS token in Firebase Cloud Messaging
    /// and returns firebase tokens for each APNS token
    public func registerAPNS(
        appBundleId: String,
        serverKey: String? = nil,
        sandbox: Bool = false,
        tokens: String...,
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<[APNSToFirebaseToken]> {
        registerAPNS(appBundleId: appBundleId, serverKey: serverKey, sandbox: sandbox, tokens: tokens, on: eventLoop)
    }
    
    /// Helper method which registers your pure APNS token in Firebase Cloud Messaging
    /// and returns firebase tokens for each APNS token
    public func registerAPNS(
        appBundleId: String,
        serverKey: String? = nil,
        sandbox: Bool = false,
        tokens: [String],
        on eventLoop: EventLoop? = nil) -> EventLoopFuture<[APNSToFirebaseToken]> {
        let eventLoop = eventLoop ?? application.eventLoopGroup.next()
        guard tokens.count <= 100 else {
            return eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "FCM: Register APNS: tokens count should be less or equeal 100"))
        }
        guard tokens.count > 0 else {
            return eventLoop.future([])
        }
        guard let configuration = self.configuration else {
            #if DEBUG
            fatalError("FCM not configured. Use app.fcm.configuration = ...")
            #else
            return eventLoop.future([])
            #endif
        }
        guard let serverKey = serverKey ?? configuration.serverKey else {
            fatalError("FCM: Register APNS: Server Key is missing.")
        }
        let url = iidURL + "batchImport"
        return eventLoop.future().flatMapThrowing { accessToken throws -> HTTPClient.Request in
            struct Payload: Codable {
                let application: String
                let sandbox: Bool
                let apns_tokens: [String]
            }
            let payload = Payload(application: appBundleId, sandbox: false, apns_tokens: tokens)
            let payloadData = try JSONEncoder().encode(payload)
            
            var headers = HTTPHeaders()
            headers.add(name: "Authorization", value: "key=\(serverKey)")
            headers.add(name: "Content-Type", value: "application/json")
            
            return try .init(url: url, method: .POST, headers: headers, body: .data(payloadData))
        }.flatMap { request in
            return self.client.execute(request: request).flatMapThrowing { res in
                guard 200 ..< 300 ~= res.status.code else {
                    guard
                        let bb = res.body,
                        let bytes = bb.getBytes(at: 0, length: bb.readableBytes),
                        let reason = String(bytes: bytes, encoding: .utf8) else {
                        throw Abort(.internalServerError, reason: "FCM: Register APNS: unable to decode error response")
                    }
                    throw Abort(.internalServerError, reason: reason)
                }
                struct Result: Codable {
                    struct Result: Codable {
                        let registration_token, apns_token, status: String
                    }
                    var results: [Result]
                }
                guard let body = res.body, let result = try? JSONDecoder().decode(Result.self, from: body) else {
                    throw Abort(.notFound, reason: "FCM: Register APNS: empty response")
                }
                return result.results.map {
                    .init(registration_token: $0.registration_token, apns_token: $0.apns_token, isRegistered: $0.status == "OK")
                }
            }
        }
    }
}