//
//  AppleErrorExplanation.swift
//  SideSign
//
//  Turns the strings Apple and the Anisette hosts actually return into something a user can act
//  on. The raw payloads are kept in the debug log; what reaches the UI is the explanation.
//

import Foundation

/// What a failure means, in the terms the person seeing it needs.
public enum AppleFailure: Equatable, Sendable {
    /// 1100 from the legacy endpoints, or a 401 NOT_AUTHORIZED from the v1 services ones. The
    /// portal session for a free personal account lasts minutes, so callers can recover by
    /// authenticating again with the credentials they already hold.
    case sessionExpired
    /// The GrandSlam headers were refused outright. Almost always the Anisette server is handing
    /// out headers from an ADI that does not match the client identity we declared with them.
    case anisetteRejected(ec: Int)
    /// Apple is answering with an HTML error page instead of a plist.
    case throttledByApple
    /// The Anisette server itself cannot start its signing engine right now.
    case serverOverloaded
    /// The stored machine identity belongs to a different Anisette server.
    case adiBoundToOtherServer
}

public extension AppleFailure {

    /// `detail` is whatever Apple or the server said; `statusCode` is the HTTP status when known.
    init?(detail: String, statusCode: Int = -1) {
        let text = detail.lowercased()

        if statusCode == HTTPStatusCodes.unauthorized
            || text.contains("session has expired")
            || text.contains("not_authorized")
        {
            self = .sessionExpired
            return
        }
        if text.contains("-80045") || text.contains("80045") {
            self = .anisetteRejected(ec: -80045)
            return
        }
        if text.contains("spawn engine worker") || text.contains("resource temporarily unavailable") {
            self = .serverOverloaded
            return
        }
        if text.contains("-45061") {
            self = .adiBoundToOtherServer
            return
        }
        if Self.isHTML(detail) {
            self = .throttledByApple
            return
        }
        return nil
    }

    var explanation: String {
        switch self {
        case .sessionExpired:
            return "Your Apple Developer portal session expired, which happens within minutes on a free Apple ID. AirStore can sign in again without you re-entering anything."
        case .anisetteRejected(let ec):
            return "Apple rejected this sign-in (\(ec)). The Anisette server in use is handing out headers that do not match the client identity sent with them. Pick a different server in Settings, or retry later."
        case .throttledByApple:
            return "Apple is temporarily refusing this request (it answered with an HTTP error page rather than a response). Wait ten to thirty minutes before signing in again; retrying right away usually extends it."
        case .serverOverloaded:
            return "The Anisette server is overloaded: it could not start its signing engine. Try again in a few minutes, or pick another server in Settings."
        case .adiBoundToOtherServer:
            return "The stored machine identity belongs to a different Anisette server. A fresh one is provisioned automatically; if this repeats, switch servers in Settings."
        }
    }

    /// Pulls the title out of an HTML error page so a payload like
    /// `<html><head><title>503 Service Temporarily Unavailable</title>...` stops being shown whole.
    static func titleOfHTML(_ payload: String) -> String? {
        guard isHTML(payload), let start = payload.range(of: "<title>", options: .caseInsensitive) else { return nil }
        let rest = payload[start.upperBound...]
        guard let end = rest.range(of: "</title>", options: .caseInsensitive) else { return nil }
        return String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isHTML(_ payload: String) -> Bool {
        let head = payload.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64).lowercased()
        return head.contains("<html") || head.contains("<!doctype html") || head.contains("<head>")
    }
}

/// Maps one Apple response into the error a caller should throw, so every dispatch path gives the
/// same wording instead of each endpoint inventing its own.
public func developerPortalError(detail: String, statusCode: Int = -1) -> Error {
    guard let failure = AppleFailure(detail: detail, statusCode: statusCode) else {
        return ServerError.underlyingError(code: statusCode, message: detail)
    }
    if case .sessionExpired = failure {
        return DeveloperPortalError.sessionExpired
    }
    return ServerError.underlyingError(code: statusCode, message: failure.explanation)
}

/// Same, for the legacy endpoints that report through `resultCode` instead of an HTTP status.
func developerPortalError(resultCode: Int, message: String) -> Error {
    if resultCode == DeveloperPortalResultCodes.sessionExpired {
        return DeveloperPortalError.sessionExpired
    }
    return developerPortalError(detail: "\(message) (\(resultCode))", statusCode: -1)
}
