import AppIntents
import WidgetKit

/// Widget configuration intent — long-press 编辑 widget 弹出的"系列"选择器。
///
/// 替代旧的 StaticConfiguration:之前 widget 一律显示"四系列里最早未结束的一场",
/// 用户没法 pin 自己只关心的系列(F1 粉只想看 F1)。
/// 现在每个 widget instance 各自存配置,主屏可以放多个 widget,
/// 分别钉不同系列。
public struct SelectSeriesIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource = "选择系列"
    public static var description = IntentDescription("Show next race for a specific motorsport series or all series.")

    @Parameter(title: "系列", default: .all)
    public var series: SeriesSelection

    public init() {}

    public init(series: SeriesSelection) {
        self.series = series
    }
}

/// Widget-side 系列枚举。
/// - 不直接依赖主 app 的 `MotorsportSeries`(widget extension 不 link 整个 PoleDomain)。
/// - raw value 与 `WidgetSnapshot.NextRace.seriesRaw` 对齐:
///   `"f1" / "motogp" / "wssp" / "fe"`。
///   注意 WSBK 在 snapshot 里 raw 是 "wssp"(WorldSSP 中量级 class),
///   面向用户展示走 SeriesBrand.shortName 转 "WSBK"。
public enum SeriesSelection: String, AppEnum, CaseIterable {
    case all
    case f1
    case motogp
    case wsbk
    case fe

    /// 把 enum case 映射到 snapshot 的 seriesRaw 字符串。
    /// `.all` 返 nil(不过滤),其余直接对齐 raw value。
    public var seriesRaw: String? {
        switch self {
        case .all:    return nil
        case .f1:     return "f1"
        case .motogp: return "motogp"
        case .wsbk:   return "wssp"   // snapshot 用 wssp(WorldSSP class)作 raw
        case .fe:     return "fe"
        }
    }

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Series Selection"

    public static var caseDisplayRepresentations: [SeriesSelection: DisplayRepresentation] = [
        .all:    "全部 / All",
        .f1:     "Formula 1",
        .motogp: "MotoGP",
        .wsbk:   "WorldSBK",
        .fe:     "Formula E",
    ]
}
