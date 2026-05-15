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
            case .sprint:         return L10n.t(zh: "冲刺赛", en: "Sprint")
            case .qualifying:     return L10n.t(zh: "排位", en: "Qualifying")
            case .sprintShootout: return L10n.t(zh: "冲刺排位", en: "S Quali")
            case .practice:       return L10n.t(zh: "练习", en: "Practice")
            }
        }
    }

    public let id: String           // event 内稳定 slug，如 "2025-1-fp1" / "2025-1-race-2"
    public let kind: Kind
    public let label: String        // UI 直显："FP1" / "Q3" / "Sprint" / "Race 2" / "Superpole Race"
    public let startTime: Date
    public let durationMinutes: Int?

    /// 在中文模式下将 session 名翻译为中文；英文模式 pass-through 返回 `label`。
    /// FP1/FP2/FP3/Q1/Q2/Q3 等带数字编号的 label 直接透传，不做翻译。
    public var localizedLabel: String {
        guard L10n.effective == .zh else { return label }
        switch kind {
        case .sprint:         return "冲刺赛"
        case .sprintShootout: return "冲刺排位赛"
        case .race:
            let up = label.uppercased()
            if up == "RACE" || up == "RACE 1" || up == "RACE 2" { return up == "RACE 1" ? "正赛 1" : up == "RACE 2" ? "正赛 2" : "正赛" }
            return label
        case .qualifying:
            if label.uppercased() == "QUALIFYING" { return "排位赛" }
            return label   // Q1/Q2/Q3/Superpole 透传
        case .practice:
            if label.uppercased() == "PRACTICE" { return "练习" }
            return label   // FP1/FP2/Warm Up 透传
        case .superpoleRace:
            return label   // "Superpole Race" — 专有名词，透传
        }
    }

    public init(id: String, kind: Kind, label: String, startTime: Date, durationMinutes: Int? = nil) {
        self.id = id
        self.kind = kind
        self.label = label
        self.startTime = startTime
        self.durationMinutes = durationMinutes
    }

    /// 默认 session 时长——给 EventKit end date 用,不同 session 类型给不同时长。
    /// 历史上每个 detail view + AddToCalendarTool 各持一份私有 extension,
    /// Wave 6 提到 PoleDomain 统一暴露,避免重复定义。
    public var defaultDuration: TimeInterval {
        switch kind {
        case .race:           return 2 * 3600        // 2h
        case .sprint:         return 45 * 60          // 45min
        case .superpoleRace:  return 30 * 60          // 30min
        case .qualifying:     return 60 * 60          // 1h
        case .sprintShootout: return 30 * 60
        case .practice:       return 60 * 60
        }
    }
}
