import SwiftUI
import PoleDesignSystem

/// 每个 series 一个品牌主题——颜色 + 渐变 + 字体 hint。
/// 参考 Ferrari / Repsol Honda / WorldSBK Pirelli 等官方品牌色。
public extension MotorsportSeries {
    var brandColor: Color {
        switch self {
        case .f1:     return Color(red: 0.882, green: 0.024, blue: 0.000)   // F1 红 #E10600
        case .motogp: return Color(red: 1.000, green: 0.420, blue: 0.000)   // MotoGP 橙 #FF6B00
        case .wssp:   return Color(red: 0.000, green: 0.624, blue: 0.302)   // WSBK 绿 #009F4D
        case .fe:     return Color(red: 0.000, green: 0.784, blue: 0.769)   // Formula E 青 #00C8C4
        }
    }

    /// WCAG AA 4.5:1 兼容版 brand color — 用于"白色文字底色"或"深底文字色"等需要对比度的场景。
    /// 老 brandColor 的 FE 青 ~2.1:1 / WSBK 绿 ~3.4:1 在白文上不达标,这里给暗化变体。
    /// `StatusBadge` 等白文场景应用此变体而非原 brandColor。
    var brandColorAccessible: Color {
        switch self {
        case .f1:     return Color(red: 0.700, green: 0.000, blue: 0.000)   // 深红 #B30000(AA 7:1)
        case .motogp: return Color(red: 0.760, green: 0.310, blue: 0.000)   // 深橙 #C25000(AA 4.6:1)
        case .wssp:   return Color(red: 0.000, green: 0.459, blue: 0.224)   // 深绿 #00753A(AA 4.7:1)
        case .fe:     return Color(red: 0.000, green: 0.478, blue: 0.467)   // 深青 #007A77(AA 4.6:1)
        }
    }

    /// 主色到亮色的线性渐变(给 banner / 卡片左条用)。
    var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandColor, brandColor.opacity(0.7)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - 全局非 series 色板

public enum BrandPalette {
    /// app 级 accent — 改用 F1 官方红 #E10600(最赛车圈认知度,跨系列中性)。
    /// 紫色不符合赛车视觉语言,2026 改造去掉。
    public static let appAccent = Color(red: 0.882, green: 0.024, blue: 0.000)   // #E10600 F1 红

    // hero CTA 渐变 — 红到亮红(统一走 DS.Palette.racingGradient 避免重复定义)
    public static let aiGradient = DS.Palette.racingGradient

    /// 状态色:live / upcoming / finished / postponed
    public static let liveRed     = Color(red: 0.937, green: 0.267, blue: 0.267)
    public static let upcomingBlue = Color(red: 0.000, green: 0.478, blue: 1.000)
    public static let finishedGray = Color.gray
    public static let postponedAmber = Color.orange
}

public extension EventStatus {
    var brandColor: Color {
        switch self {
        case .live:      return BrandPalette.liveRed
        case .upcoming:  return BrandPalette.upcomingBlue
        case .finished:  return BrandPalette.finishedGray
        case .postponed: return BrandPalette.postponedAmber
        }
    }

    var displayLabel: String {
        switch self {
        case .live:      return L10n.t(zh: "进行中", en: "Live")
        case .upcoming:  return L10n.t(zh: "待举行", en: "Upcoming")
        case .finished:  return L10n.t(zh: "已结束", en: "Finished")
        case .postponed: return L10n.t(zh: "延期", en: "Postponed")
        }
    }
}
