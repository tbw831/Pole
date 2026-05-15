import SwiftUI
import PoleDomain
import PoleMotorsportKit

/// 赛车 tab 容器——顶部 segmented picker 在"全部 / F1 / MotoGP / WSSP / FE"切换。
/// "全部"渲染 MotorsportTimelineView 跨 series 时间线;其它走各 series 自己的 list view。
public struct MotorsportListView: View {
    public init() {}
    /// rawValue 是 stable id(给 Picker / persistence 用,中英都不变);
    /// 用户可见标题走 displayName。
    enum Filter: String, CaseIterable, Identifiable {
        case all = "all"
        case f1 = "f1"
        case motogp = "motogp"
        case wssp = "wssp"
        case fe = "fe"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all:    return L10n.t(zh: "全部", en: "All")
            case .f1:     return "F1"
            case .motogp: return "MotoGP"
            case .wssp:   return "WSBK"
            case .fe:     return "FE"
            }
        }
    }

    @State private var filter: Filter = .all

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Series", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch filter {
            case .all:    MotorsportTimelineView()
            case .f1:     RaceListView()
            case .motogp: MotoGPRoundListView()
            case .wssp:   WSBKRoundListView()
            case .fe:     FERoundListView()
            }
        }
    }
}
