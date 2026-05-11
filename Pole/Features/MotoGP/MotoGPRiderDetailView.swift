import SwiftUI
import Charts

@MainActor
@Observable
final class MotoGPRiderDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(rounds: [MotoGPRiderRoundPoints])
        case failed(message: String)
    }

    let riderId: String
    private(set) var state: State = .idle

    init(riderId: String) {
        self.riderId = riderId
    }

    /// MotoGPClient.fetchRiderRoundPoints 内部 try? 静默失败,
    /// 这里 catch 不到错误——空数组就是"加载完但没数据"。
    func load() async {
        state = .loading
        let rounds = await MotoGPClient.shared.fetchRiderRoundPoints(riderId: riderId)
        state = .loaded(rounds: rounds)
    }
}

/// MotoGP 车手详情 — 跟 F1DriverDetailView 同款结构(头部 → 简介 → 趋势图 → 赛季回顾 → 各场积分)。
/// 每个 round 含 race + sprint 两段得分,趋势图按 totalPoints 累加。
struct MotoGPRiderDetailView: View {
    let standing: MotoGPRiderStanding
    @State private var viewModel: MotoGPRiderDetailViewModel

    init(standing: MotoGPRiderStanding) {
        self.standing = standing
        _viewModel = State(initialValue: MotoGPRiderDetailViewModel(riderId: standing.rider.id))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(standing.rider.displayFullName)
                        .font(.title2.weight(.semibold))
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        if let n = standing.rider.number {
                            Text("#\(n)")
                                .font(DS.Font.numberLarge)
                                .foregroundStyle(MotorsportSeries.motogp.brandColor)
                        }
                        if let iso = standing.rider.countryISO {
                            Text(iso)
                                .font(DS.Font.numberSmall)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("MotoGP · \(standing.team.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            WikipediaSummarySection(queryTitle: standing.rider.fullName, series: .motogp)
            chartSection
            Section(L10n.t(zh: "赛季成绩", en: "Season Stats")) {
                LabeledContent(L10n.t(zh: "当前排名", en: "Position"),
                               value: L10n.t(zh: "第 \(standing.position) 位", en: "P\(standing.position)"))
                LabeledContent(L10n.t(zh: "积分", en: "Points"), value: standing.points.formatted(.number))
                LabeledContent(L10n.t(zh: "胜场", en: "Wins"), value: "\(standing.raceWins)")
                LabeledContent(L10n.t(zh: "领奖台", en: "Podiums"), value: "\(standing.podiums)")
            }
            seasonReviewSection
            roundsSection
        }
        .dsDetailList()
        .navigationTitle(standing.rider.displayFullName)
        .navigationBarTitleDisplayMode(.inline)
        .tint(MotorsportSeries.motogp.brandColor)
        .task {
            if case .idle = viewModel.state { await viewModel.load() }
        }
        .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var chartSection: some View {
        switch viewModel.state {
        case .idle, .loading:
            Section(L10n.t(zh: "累计积分", en: "Cumulative Points")) {
                HStack { ProgressView(); Text(L10n.t(zh: "加载中…", en: "Loading…")).foregroundStyle(.secondary) }
            }
        case .failed(let message):
            Section(L10n.t(zh: "累计积分", en: "Cumulative Points")) {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        case .loaded(let rounds):
            if rounds.isEmpty {
                Section(L10n.t(zh: "累计积分", en: "Cumulative Points")) {
                    Text(L10n.t(zh: "赛季还没数据", en: "No data yet for this season")).foregroundStyle(.secondary)
                }
            } else {
                Section(L10n.t(zh: "累计积分趋势", en: "Cumulative Points Trend")) {
                    Chart(cumulativeData(rounds)) { entry in
                        LineMark(
                            x: .value("Round", entry.round),
                            y: .value("Points", entry.cumulative)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.tint)
                        PointMark(
                            x: .value("Round", entry.round),
                            y: .value("Points", entry.cumulative)
                        )
                        .foregroundStyle(.tint)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 1))
                    }
                    .frame(height: 220)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var roundsSection: some View {
        if case .loaded(let rounds) = viewModel.state, !rounds.isEmpty {
            Section(L10n.t(zh: "各场积分", en: "Points per Round")) {
                ForEach(rounds) { entry in
                    HStack(spacing: DS.Spacing.sm) {
                        Text("R\(entry.round)")
                            .font(DS.Font.numberSmall)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        Text(entry.roundName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        // 同时展示 sprint + race 拆分,方便看是哪个 session 拿的分
                        if entry.sprintPoints > 0 {
                            Text("\(L10n.t(zh: "短赛", en: "Spr")) \(entry.sprintPoints, format: .number)")
                                .font(DS.Font.numberSmall)
                                .foregroundStyle(.tertiary)
                        }
                        Text("+\(entry.totalPoints, format: .number)")
                            .font(DS.Font.numberMid)
                            .foregroundStyle(entry.totalPoints > 0 ? .primary : .tertiary)
                    }
                }
            }
        }
    }

    /// AI 赛季回顾 — loaded(rounds non-empty) 时给 LLM 真正的 round-by-round 数据;
    /// 数据没拉到时退回 standings 汇总(原来那份)。
    /// 把 rounds 先从 @MainActor viewModel 取出 snapshot,再 capture 进 @Sendable closure,
    /// 避免在 closure 内访问 @MainActor 数据触发 Swift 6 隔离错误。
    @ViewBuilder
    private var seasonReviewSection: some View {
        let snapshotRounds: [MotoGPRiderRoundPoints] = {
            if case .loaded(let rounds) = viewModel.state { return rounds }
            return []
        }()
        DriverSeasonReviewSection(
            driverName: standing.rider.displayFullName,
            series: .motogp,
            dataProvider: { [standing, snapshotRounds] in
                if !snapshotRounds.isEmpty {
                    let total = snapshotRounds.reduce(0.0) { $0 + $1.totalPoints }
                    let payload: [String: Any] = [
                        "driver": standing.rider.fullName,
                        "team": standing.team.name,
                        "constructor": standing.constructor.name,
                        "position": standing.position,
                        "total_points": total,
                        "rounds": snapshotRounds.map {
                            ["round": $0.round,
                             "race_name": $0.roundName,
                             "race_points": $0.racePoints,
                             "sprint_points": $0.sprintPoints,
                             "total_points": $0.totalPoints]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
                // round-by-round 没拉到 → 退回 standings 汇总(LLM 至少有点信息可用)
                let payload: [String: Any] = [
                    "driver": standing.rider.fullName,
                    "team": standing.team.name,
                    "constructor": standing.constructor.name,
                    "position": standing.position,
                    "points": standing.points,
                    "wins": standing.raceWins,
                    "podiums": standing.podiums
                ]
                let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                return String(data: data, encoding: .utf8) ?? "{}"
            }
        )
    }

    /// 累计积分曲线数据点(race + sprint 都计入)
    private func cumulativeData(_ rounds: [MotoGPRiderRoundPoints]) -> [CumulativePoint] {
        var sum: Double = 0
        return rounds.map { e in
            sum += e.totalPoints
            return CumulativePoint(round: e.round, cumulative: sum)
        }
    }

    private struct CumulativePoint: Identifiable {
        let round: Int
        let cumulative: Double
        var id: Int { round }
    }
}
