import Foundation

/// 比赛周末单个 session（练习/排位/冲刺/正赛）。
/// 三种系列覆盖如下：
///   F1    : FP1/FP2/FP3 + Q1/Q2/Q3（或 SQ）+ Sprint(可选) + Race
///   MotoGP: FP1/FP2/PR + Q1/Q2 + Sprint + Race
///   WSBK  : FP1/FP2 + Superpole(Q) + Race1 + Superpole Race + Race2
public nonisolated struct Session: Hashable, Sendable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case practice           // FP1/FP2/FP3/PR/WUP
        case qualifying         // Q/Q1/Q2/Q3/SQ/Superpole
        case sprintShootout     // F1 sprint 排位
        case sprint             // F1/MotoGP 周六 sprint race
        case superpoleRace      // WSBK 周日早晨 10 圈短赛（独立于 sprint）
        case race               // 正赛 / Race 1 / Race 2

        /// session 类型徽标短文案,4 个 detail view 通用。
        public var displayLabel: String {
            switch self {
            case .race:           return L10n.t(zh: "正赛", en: "Race")
            case .superpoleRace:  return L10n.t(zh: "短赛", en: "SP Race")
            case .sprint:         return L10n.t(zh: "Sprint", en: "Sprint")
            case .qualifying:     return L10n.t(zh: "排位", en: "Qualifying")
            case .sprintShootout: return L10n.t(zh: "S 排位", en: "S Quali")
            case .practice:       return L10n.t(zh: "练习", en: "Practice")
            }
        }
    }

    public let id: String           // event 内稳定 slug，如 "2025-1-fp1" / "2025-1-race-2"
    public let kind: Kind
    public let label: String        // UI 直显："FP1" / "Q3" / "Sprint" / "Race 2" / "Superpole Race"
    public let startTime: Date
    public let durationMinutes: Int?

    public init(id: String, kind: Kind, label: String, startTime: Date, durationMinutes: Int? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.startTime = startTime
        self.durationMinutes = durationMinutes
    }
}
