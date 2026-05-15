import Foundation

// MARK: - L10n 全部 nonisolated
//
// 项目开启了 Swift 6 严格并发(或 main-actor-by-default 模块推断),enum 默认会推断成
// @MainActor。但 L10n 实际上只读 UserDefaults / Locale.current —— 都是 thread-safe,
// 根本不需要 MainActor 隔离。把整个 enum + 嵌套类型标 nonisolated 让它能从
// `nonisolated struct F1Race` 等纯领域类型调用,不引入隔离冲突。
//
// 注意:Sendable conformance 也必须 nonisolated(默认 isolated conformance 会导致
// "main actor-isolated conformance of 'Language' to 'Equatable'" 警告)。

/// 语言切换模式 —— 用户在设置里切。
public nonisolated enum LanguageMode: String, CaseIterable, Identifiable, Sendable {
    case zh   = "zh"     // 中文
    case en   = "en"     // English
    case auto = "auto"   // 跟随系统

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zh:   return "中文"
        case .en:   return "English"
        case .auto: return "跟随系统 / Auto"
        }
    }
}

/// 全局语言查询入口 —— 所有 Localization mapping 函数顶部用 `L10n.effective` 判断。
public nonisolated enum L10n {
    /// 用户选择的模式(从 UserDefaults)。
    public static var current: LanguageMode {
        let raw = UserDefaults.standard.string(forKey: "languageMode") ?? LanguageMode.zh.rawValue
        return LanguageMode(rawValue: raw) ?? .zh
    }

    /// 实际生效语言(auto 看系统 locale)。
    public enum Language: Sendable, Equatable {
        case zh, en
    }

    public static var effective: Language {
        switch current {
        case .zh: return .zh
        case .en: return .en
        case .auto:
            let lang = Locale.current.language.languageCode?.identifier ?? ""
            return lang.hasPrefix("zh") ? .zh : .en
        }
    }

    /// 二选一短串(中/英),根据当前语言返。view 里用法:`L10n.t(zh: "赛车", en: "Racing")`。
    public static func t(zh: String, en: String) -> String {
        effective == .en ? en : zh
    }
}
