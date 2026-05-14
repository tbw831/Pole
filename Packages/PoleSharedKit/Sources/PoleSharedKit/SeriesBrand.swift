import SwiftUI

/// 给 widget extension 用的品牌色查表。
/// 主 app 仍用 Theme/SeriesTheme.swift 的 MotorsportSeries.brandColor。
/// 这两份必须保持颜色值同步——加新系列时两个文件都要更新。
public enum SeriesBrand {
    public static func color(forRaw raw: String) -> Color {
        switch raw {
        case "f1":     return Color(red: 0.882, green: 0.024, blue: 0.000)   // #E10600
        case "motogp": return Color(red: 1.000, green: 0.420, blue: 0.000)   // #FF6B00
        case "wssp":   return Color(red: 0.000, green: 0.624, blue: 0.302)   // #009F4D
        case "fe":     return Color(red: 0.000, green: 0.784, blue: 0.769)   // #00C8C4
        default:       return Color.gray
        }
    }

    public static func gradient(forRaw raw: String) -> LinearGradient {
        let base = color(forRaw: raw)
        return LinearGradient(
            colors: [base, base.opacity(0.7)],
            startPoint: .top, endPoint: .bottom
        )
    }

    public static func displayName(forRaw raw: String) -> String {
        switch raw {
        case "f1":     return "Formula 1"
        case "motogp": return "MotoGP"
        case "wssp":   return "WorldSBK"
        case "fe":     return "Formula E"
        default:       return raw.uppercased()
        }
    }

    public static func shortName(forRaw raw: String) -> String {
        switch raw {
        case "f1":     return "F1"
        case "motogp": return "MotoGP"
        case "wssp":   return "WSBK"
        case "fe":     return "FE"
        default:       return raw.uppercased()
        }
    }
}
