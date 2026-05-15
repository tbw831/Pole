import Foundation

/// 赛道。F1/MotoGP/WSBK 共用。
/// id 用稳定 slug——F1 沿用 jolpica circuitId（"bahrain"），其他系列用各自 API 的稳定标识。
public nonisolated struct Circuit: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let locality: String
    public let country: String

    public init(id: String, name: String, locality: String, country: String) {
        self.id = id
        self.name = name
        self.locality = locality
        self.country = country
    }
}
