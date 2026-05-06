import SwiftUI

/// 外观模式 — 用户在设置里切;PoleApp 通过 `.preferredColorScheme(...)` 应用。
public nonisolated enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system = "system"   // 跟随系统
    case light  = "light"    // 浅色
    case dark   = "dark"     // 深色(夜间)

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return L10n.t(zh: "跟随系统", en: "System")
        case .light:  return L10n.t(zh: "浅色", en: "Light")
        case .dark:   return L10n.t(zh: "深色", en: "Dark")
        }
    }

    /// 转成 SwiftUI 用的 ColorScheme;`.system` 返 nil 让系统决定。
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
