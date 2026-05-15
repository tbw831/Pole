import Foundation

/// 赛车系列（F1 / MotoGP / WSSP / …）。
/// 对应 League.series 字段；决定数据源、积分规则、UI 模板、官方配色。
/// 加新系列只在此处加 case + displayName + shortName。
public nonisolated enum MotorsportSeries: String, Sendable, Codable, CaseIterable, Identifiable {
    case f1
    case motogp
    /// WorldSSP（中量级，worldsbk.com 顶层组织 WorldSBK 下的子 class）。
    /// 数据源代码目录叫 WSBK 因为后端是 worldsbk.com，但本 series 只关心 WSSP class。
    case wssp
    /// Formula E (FIA 电动方程式)。Pulselive API,跟 MotoGP 同平台不同 endpoint。
    case fe
    // 扩展位：f2, f3, moto2, moto3, motoE, indycar, wec, wrc, nascar …

    public var id: String { rawValue }
    public var sport: Sport { .motorsport }

    /// displayName / shortName 是国际通用品牌名,中英一致,L10n 不切。
    public var displayName: String {
        switch self {
        case .f1:     return "Formula 1"
        case .motogp: return "MotoGP"
        case .wssp:   return "WorldSBK"   // 品牌名,跟 F1/MotoGP 平齐;数据是其下 WSSP class
        case .fe:     return "Formula E"
        }
    }

    public var shortName: String {
        switch self {
        case .f1:     return "F1"
        case .motogp: return "MotoGP"
        case .wssp:   return "WSBK"
        case .fe:     return "FE"
        }
    }
}
