import SwiftUI
import PoleDesignSystem
import PoleDomain
import PoleMotorsportKit

@MainActor
@Observable
final class MotorsportTimelineViewModel {
    enum State {
        case idle
        case loading
        /// 已加载 — `groups` 已经分桶完成,view 只负责渲染。
        /// 之前是 `loaded(rounds:)` + view body 调 `groupByBucket(rounds)`,80+ 条赛程
        /// 每帧重算 + dateComponents 计算,首屏 stutter / orientation/refreshable 重算。
        case loaded(groups: [MotorsportTimelineView.BucketGroup])
        case failed(message: String)
    }

    /// 一行展示数据 — `load()` 时把 `currentStatus`(基于 `Date()` 实时算)冻结成 snapshot,
    /// row body 不再每帧重算 status 和 date range。
    /// 80+ 条 list 滚动时每帧节省 80 次 dateComponents 计算 + 80 次 status 比较。
    struct RoundSnapshot: Identifiable, Hashable {
        let round: AnyMotorsportRound
        let isLive: Bool
        let statusSnapshot: EventStatus
        let weekendDateRange: String

        var id: String { "\(round.series.rawValue):\(round.id)" }
    }

    private(set) var state: State = .idle

    /// 把连续同赛道的 FE round 合并为 feWeekend（与 FERoundListViewModel 同逻辑）。
    private static func mergeFERounds(_ rounds: [FERound]) -> [AnyMotorsportRound] {
        var result: [AnyMotorsportRound] = []
        var buffer: [FERound] = []
        for round in rounds {
            if let last = buffer.last, last.circuit.name != round.circuit.name {
                result.append(buffer.count > 1 ? .feWeekend(FEWeekend(rounds: buffer)) : .fe(buffer[0]))
                buffer = []
            }
            buffer.append(round)
        }
        if let last = buffer.last {
            result.append(buffer.count > 1 ? .feWeekend(FEWeekend(rounds: buffer)) : .fe(last))
        }
        return result
    }

    func load() async {
        state = .loading
        // 三 series 并发拉,任一失败不阻塞其他;失败 series 当成空数组处理
        async let f1Task = (try? await JolpicaClient.shared.fetchSeasonRaces()) ?? []
        async let motogpTask = (try? await MotoGPClient.shared.fetchSeasonRounds()) ?? []
        async let wsspTask = (try? await WSBKClient.shared.fetchSeasonRounds()) ?? []
        async let feTask = (try? await FormulaEClient.shared.fetchSeasonRounds()) ?? []
        let (f1, motogp, wssp, fe) = await (f1Task, motogpTask, wsspTask, feTask)

        let combined: [AnyMotorsportRound] =
            f1.map(AnyMotorsportRound.f1)
            + motogp.map(AnyMotorsportRound.motogp)
            + wssp.map(AnyMotorsportRound.wssp)
            + Self.mergeFERounds(fe)

        // 只保留"未结束"的(进行中 + 未开始)——已结束的去对应 series 单独 tab 看
        let now = Date()
        let upcoming = combined.filter { $0.weekendEnd >= now }

        // live 排第一,其余按 weekendStart 升序
        let sorted = upcoming.sorted { a, b in
            let aLive = a.currentStatus == .live
            let bLive = b.currentStatus == .live
            if aLive != bLive { return aLive }
            return a.weekendStart < b.weekendStart
        }

        if sorted.isEmpty {
            state = .failed(message: L10n.t(zh: "所有系列数据都拉不到,检查网络",
                                            en: "Failed to load any series, check network"))
        } else {
            // 一次性算分桶 — view body 直接 ForEach(groups) 不再每帧重算
            let groups = MotorsportTimelineView.groupByBucket(sorted, now: now)
            state = .loaded(groups: groups)
        }
    }
}

struct MotorsportTimelineView: View {
    @State private var viewModel = MotorsportTimelineViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.t(zh: "赛车日程", en: "Racing Schedule"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    if case .idle = viewModel.state {
                        await viewModel.load()
                    }
                }
                .refreshable { await viewModel.load() }
                .navigationDestination(for: F1Race.self) { RaceDetailView(race: $0) }
                .navigationDestination(for: F1SessionResultsRef.self) { F1SessionResultsView(ref: $0) }
                .navigationDestination(for: MotoGPRound.self) { MotoGPRoundDetailView(round: $0) }
                .navigationDestination(for: MotoGPSessionRef.self) { MotoGPSessionResultsView(ref: $0) }
                .navigationDestination(for: WSBKRound.self) { WSBKRoundDetailView(round: $0) }
                .navigationDestination(for: WSSPSessionWithResults.self) { WSSPSessionResultsView(item: $0) }
                .navigationDestination(for: FERound.self) { FERoundDetailView(route: .single($0)) }
                .navigationDestination(for: FERoute.self) { FERoundDetailView(route: $0) }
                .navigationDestination(for: FESessionRef.self) { FESessionResultsView(ref: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载中…", en: "Loading…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let groups):
            if groups.isEmpty {
                VStack(spacing: DS.Spacing.lg) {
                    StartLightGrid(mode: .idle, size: 16)
                    Text(L10n.t(zh: "本月无赛事", en: "No rounds this month"))
                        .font(DS.Font.heroSubtitle)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .padding()
                .background(
                    CheckerStripe(.fill, opacity: 0.04)
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.bucket) { group in
                            Section {
                                ForEach(group.snapshots) { snap in
                                    row(for: snap)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } header: {
                                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                                    Rectangle()
                                        .fill(DS.Palette.racingRed)
                                        .frame(width: 3, height: 22)
                                    Text(group.bucket.label.uppercased())
                                        .font(DS.Font.heroTitle)
                                        .foregroundStyle(.primary)
                                        .tracking(1.2)
                                    Spacer()
                                }
                                .padding(.vertical, DS.Spacing.sm)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.load() } }
        }
    }

    /// 不同 series 走不同 NavigationLink 类型,destination 已在 NavigationStack 上注册。
    /// `.buttonStyle(.plain)` — 否则系统会把 NavigationLink 内文字染成 tint(紫色)。
    @ViewBuilder
    private func row(for snap: MotorsportTimelineViewModel.RoundSnapshot) -> some View {
        switch snap.round {
        case .f1(let race):
            NavigationLink(value: race) { TimelineRow(snapshot: snap) }.buttonStyle(.plain)
        case .motogp(let r):
            NavigationLink(value: r) { TimelineRow(snapshot: snap) }.buttonStyle(.plain)
        case .wssp(let r):
            NavigationLink(value: r) { TimelineRow(snapshot: snap) }.buttonStyle(.plain)
        case .fe(let r):
            NavigationLink(value: r) { TimelineRow(snapshot: snap) }.buttonStyle(.plain)
        case .feWeekend(let w):
            NavigationLink(value: FERoute.weekend(w)) { TimelineRow(snapshot: snap) }.buttonStyle(.plain)
        }
    }

    // MARK: - 分组(按"本周/下周/X 月"等 bucket)

    enum DateBucket: Hashable {
        case live              // 进行中
        case thisWeek          // 本周末(今天 ≤ 起始 < 7 天后)
        case nextWeek          // 下周末(7-14 天)
        case month(Int, Int)   // 某月(year, month)
        case later             // 更远

        var label: String {
            switch self {
            case .live:                return L10n.t(zh: "进行中", en: "Live")
            case .thisWeek:            return L10n.t(zh: "本周末", en: "This Weekend")
            case .nextWeek:            return L10n.t(zh: "下周", en: "Next Week")
            case .month(_, let month): return L10n.t(zh: "\(month) 月", en: monthEnglish(month))
            case .later:               return L10n.t(zh: "更远", en: "Later")
            }
        }

        private func monthEnglish(_ m: Int) -> String {
            let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            guard (1...12).contains(m) else { return "\(m)" }
            return names[m - 1]
        }

        /// 排序权重,小的优先。
        var sortKey: Int {
            switch self {
            case .live:                return -1000
            case .thisWeek:            return -100
            case .nextWeek:            return -50
            case .month(let y, let m): return y * 100 + m
            case .later:               return 1_000_000
            }
        }
    }

    struct BucketGroup {
        let bucket: DateBucket
        let snapshots: [MotorsportTimelineViewModel.RoundSnapshot]
    }

    static func groupByBucket(_ rounds: [AnyMotorsportRound], now: Date = .now) -> [BucketGroup] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let in7days = calendar.date(byAdding: .day, value: 7, to: today)!
        let in14days = calendar.date(byAdding: .day, value: 14, to: today)!

        // 一次性把 currentStatus 和 dateRange 算成 snapshot,row body 不再每帧重算。
        let snapshots: [MotorsportTimelineViewModel.RoundSnapshot] = rounds.map { round in
            let status = round.currentStatus
            let s = round.weekendStart.formatted(.dateTime.month(.abbreviated).day().beijing())
            let e = round.weekendEnd.formatted(.dateTime.month(.abbreviated).day().beijing())
            return .init(round: round,
                         isLive: status == .live,
                         statusSnapshot: status,
                         weekendDateRange: "\(s) – \(e)")
        }

        var buckets: [DateBucket: [MotorsportTimelineViewModel.RoundSnapshot]] = [:]
        for snap in snapshots {
            let bucket: DateBucket
            if snap.isLive {
                bucket = .live
            } else if snap.round.weekendStart < in7days {
                bucket = .thisWeek
            } else if snap.round.weekendStart < in14days {
                bucket = .nextWeek
            } else {
                let comps = calendar.dateComponents([.year, .month], from: snap.round.weekendStart)
                if let y = comps.year, let m = comps.month {
                    bucket = .month(y, m)
                } else {
                    bucket = .later
                }
            }
            buckets[bucket, default: []].append(snap)
        }
        return buckets
            .sorted { $0.key.sortKey < $1.key.sortKey }
            .map { BucketGroup(bucket: $0.key, snapshots: $0.value) }
    }
}

// MARK: - Row

private struct TimelineRow: View {
    let snapshot: MotorsportTimelineViewModel.RoundSnapshot

    var body: some View {
        let round = snapshot.round
        MotorsportCard(series: round.series, isLive: snapshot.isLive) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(round.series.shortName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(round.series.brandColor)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(snapshot.weekendDateRange)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(round.headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Text(round.subheadline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } trailing: {
            StatusBadge(status: snapshot.statusSnapshot)
        }
        // VoiceOver:整张卡片合并成一个元素,一次读完"系列 标题 副标题 日期 状态",
        // 不再逐个 Text 朗读 5-7 次。点击行为(NavigationLink)由外层提供。
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(round.series.shortName) \(round.headline). \(round.subheadline). \(snapshot.weekendDateRange). \(snapshot.statusSnapshot.displayLabel)")
        .accessibilityHint(L10n.t(zh: "查看赛事详情", en: "View race details"))
    }
}
