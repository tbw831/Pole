import Combine
import SwiftUI

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case dark    // 默认
    case light
    case system

    public var id: String { rawValue }

    // Alias kept for backward compatibility with SettingsView (Tasks 2-3 will migrate to displayLabel)
    public var displayName: String { displayLabel }

    public var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }

    public var displayLabel: String {
        switch self {
        case .dark:   return L10n.t(zh: "深色", en: "Dark")
        case .light:  return L10n.t(zh: "浅色", en: "Light")
        case .system: return L10n.t(zh: "跟随系统", en: "System")
        }
    }
}

@MainActor
public final class AppearanceStore: ObservableObject {
    public static let shared = AppearanceStore()
    private let key = "appearanceMode"

    @Published public var current: AppearanceMode {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: key) }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let mode = AppearanceMode(rawValue: raw) {
            self.current = mode
        } else {
            self.current = .dark   // 首次启动默认 Dark
        }
    }
}
