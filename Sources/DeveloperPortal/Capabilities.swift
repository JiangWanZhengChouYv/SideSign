//
//  Capabilities.swift
//  SideSign
//
//  The v1 (JSON:API) half of the developer portal.
//

import Foundation

/// One entry of `GET /services/v1/capabilities`. Apple's own list, per team and platform, of what
/// can be switched on for an App ID -- so the caller never has to guess which capability names a
/// free personal account is actually offered.
public struct DeveloperCapability: Codable, Sendable, Hashable {
    public struct Attributes: Codable, Sendable, Hashable {
        public let name: String?
        public let enabled: Bool?
        public let compatibility: String?
    }

    public let type: String
    public let id: String
    public let attributes: Attributes?

    public var name: String { attributes?.name ?? id }
    public var isEnabled: Bool { attributes?.enabled ?? false }
}

private struct CapabilityListResponse: Codable {
    let data: [DeveloperCapability]
}

/// `{"data": {...}}` back from the PATCH; we only care that it did not error out.
private struct BundleIDResponse: Codable {
    struct Payload: Codable { let type: String?; let id: String? }
    let data: Payload?
}

private struct BundleIDCapabilitiesDocument: Encodable {
    struct CapabilityRelationship: Encodable {
        let type: String
        let id: String
    }
    struct CapabilityWrapper: Encodable { let data: CapabilityRelationship }
    struct CapabilityEntry: Encodable {
        let type: String
        let attributes: Attributes
        let relationships: Relationships
        struct Attributes: Encodable {
            let enabled: Bool
            let settings: [String]
        }
        struct Relationships: Encodable { let capability: CapabilityWrapper }
    }
    struct Attributes: Encodable {
        let identifier: String
        let teamId: String
        let seedId: String
        let bundleType: String
        let name: String
        let hasExclusiveManagedCapabilities: Bool
    }
    struct Relationships: Encodable { let bundleIdCapabilities: CapabilityList }
    struct CapabilityList: Encodable { let data: [CapabilityEntry] }
    struct Body: Encodable {
        let type: String
        let id: String
        let attributes: Attributes
        let relationships: Relationships
    }
    let data: Body
}

public extension DeveloperPortal {

    /// The capabilities Apple offers this team for iOS apps.
    func fetchCapabilities(for team: Team, session: Session) async throws -> [DeveloperCapability] {
        debugLog("[SideSign] fetchCapabilities starting...")

        var request = URLRequest(url: Constants.URLs.capabilities)
        request.httpMethod = "GET"

        let response: CapabilityListResponse = try await sendServicesRequest(
            request,
            additionalParameters: ["filter[platform]": "IOS"],
            session: session,
            team: team
        )

        let capabilities = response.data
        debugLog("[SideSign] fetchCapabilities completed with \(capabilities.count) capability(ies): \(capabilities.map(\.id).sorted())")
        return capabilities
    }

    /// Switch capabilities on for an existing App ID.
    ///
    /// This is the endpoint that knows about `INCREASED_MEMORY_LIMIT` and friends. The legacy
    /// `ios/updateAppId.action` form call has no vocabulary for them: it answers with a fixed set of
    /// feature keys and silently drops anything else, so a memory entitlement requested that way
    /// never reaches the provisioning profile.
    func setBundleIDCapabilities(_ capabilityIDs: [String], enabled: Bool = true, for appID: AppID, team: Team, session: Session) async throws {
        debugLog("[SideSign] setBundleIDCapabilities starting...")
        verboseLog("[SideSign] AppID: \(appID.bundleIdentifier) (\(appID.identifier)), capabilities: \(capabilityIDs), enabled: \(enabled)")

        guard !capabilityIDs.isEmpty else { return }

        let document = BundleIDCapabilitiesDocument(
            data: .init(
                type: "bundleIds",
                id: appID.identifier,
                attributes: .init(
                    identifier: appID.bundleIdentifier,
                    teamId: team.identifier,
                    seedId: team.identifier,
                    bundleType: "bundle",
                    name: appID.name,
                    hasExclusiveManagedCapabilities: false
                ),
                relationships: .init(
                    bundleIdCapabilities: .init(data: capabilityIDs.map { id in
                        .init(
                            type: "bundleIdCapabilities",
                            attributes: .init(enabled: enabled, settings: []),
                            relationships: .init(capability: .init(data: .init(type: "capabilities", id: id)))
                        )
                    })
                )
            )
        )

        let body = try JSONEncoder().encode(document)

        var request = URLRequest(url: Constants.URLs.bundleIDs.appendingPathComponent(appID.identifier))
        request.httpMethod = "PATCH"

        let _: BundleIDResponse = try await sendServicesRequest(
            request,
            body: body,
            session: session,
            team: team
        )

        debugLog("[SideSign] setBundleIDCapabilities succeeded for \(appID.bundleIdentifier)")
    }
}
