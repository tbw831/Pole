import SwiftUI
import Charts

@MainActor
@Observable
final class FEDriverDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(rounds: [FEDriverRoundPoints])
        case failed(message: String)
    }

    let driverId: String
    private(set) var state: State = .idle

    init(driverId: String) {
        self.driverId = driverId
    }

    /// FormulaEClient.fetchDriverRoundPoints 内部 try? 静默失败,
    /// 这里 catch 不到错误——空数组就是"加载完但没数据"。
    func load() async {
        state = .loading
        let rounds = await FormulaEClient.shared.fetchDriverRoundPoints(driverId: driverId)
        state = .loaded(rounds: rounds)
    }
}

/// Formula E 车手详情 — 跟 F1DriverDetailView 同款结构(头部 → 简介 → 趋势图 → 赛季回顾 → 各场积分)。
/// FE 的 race results API 已含 pole(+3) / fastest lap(+1) bonus,points 字段直接是最终得分。
struct FEDriverDetailView: View {
    let standing: FEDriverStanding
    @State private var viewModel: FEDriverDetailViewModel

    init(standing: FEDriverStanding) {
        self.standing = standing
        _viewModel = State(initialValue: FEDriverDetailViewModel(driverId: standing.driver.id))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    HStack(spacing: DS.Spacing.sm) {
                        Text(standing.driver.displayFullName)
                            .font(.title2.weight(.semibold))
                        Spacer()
                        FollowToggleButton(
                            target: .athlete(id: standing.driver.id, sport: .motorsport, series: "fe"),
                            displayName: standing.driver.fullName
                        )
                    }
                    HStack(spacing: DS.Spacing.sm) {
                        if let tla = standing.driver.tla {
                            Text(tla)
                                .font(.subheadline.weight(.heavy).monospacedDigit())
                                .foregroundStyle(MotorsportSeries.fe.brandColor)
                        }
                        if let iso = standing.driver.countryISO2 {
                            Text(iso)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Formula E · \(MotorsportNames.teamName(raw: standing.teamName, series: .fe))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            WikipediaSummarySection(queryTitle: standing.driver.fullName, series: .fe)
            chartSection
            Section(L10n.t(zh: "赛季成绩", en: "Season Stats")) {
                LabeledContent(
                    L10n.t(zh: "当前排名", en: "Position"),
                    value: L10n.t(zh: "第 \(standing.position) 位", en: "P\(standing.position)")
                )
                LabeledContent(
                    L10n.t(zh: "积分", en: "Points"),
                    value: standing.points.formatted(.number)
                )
            }
            seasonReviewSection
            roundsSection
        }
        .dsDetailList()
        .navigationTitle(standing.driver.displayFullName)
        .navigationBarTitleDisplayMode(.inline)
        .tint(MotorsportSeries.fe.brandColor)
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
                        Text(Localization.feRaceName(entry.roundName))
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        // pole / fastest lap bonus 标记
                        if entry.polePosition || entry.fastestLap {
                            Text(bonusFlags(entry))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(MotorsportSeries.fe.brandColor)
                        }
                        Text("+\(entry.points, format: .number)")
                            .font(DS.Font.numberMid)
                            .foregroundStyle(entry.points > 0 ? .primary : .tertiary)
                    }
                }
            }
        }
    }

    private func bonusFlags(_ entry: FEDriverRoundPoints) -> String {
        var flags: [String] = []
        if entry.polePosition { flags.append("P") }
        if entry.fastestLap { flags.append("FL") }
        return flags.joined(separator: " ")
    }

    /// AI 赛季回顾 — loaded(rounds non-empty) 时给 LLM round-by-round 数据;否则退回 standings 汇总。
    /// 先把 rounds snapshot 出来再捕获进 @Sendable closure,避免 @MainActor 隔离错误。
    @ViewBuilder
    private var seasonReviewSection: some View {
        let snapshotRounds: [FEDriverRoundPoints] = {
            if case .loaded(let rounds) = viewModel.state { return rounds }
            return []
        }()
        DriverSeasonReviewSection(
            driverName: standing.driver.displayFullName,
            series: .fe,
            dataProvider: { [standing, snapshotRounds] in
                if !snapshotRounds.isEmpty {
                    let total = snapshotRounds.reduce(0.0) { $0 + $1.points }
                    let payload: [String: Any] = [
                        "driver": standing.driver.fullName,
                        "team": standing.teamName,
                        "position": standing.position,
                        "total_points": total,
                        "rounds": snapshotRounds.map {
                            ["round": $0.round,
                             "race_name": $0.roundName,
                             "points": $0.points,
                             "pole": $0.polePosition,
                             "fastest_lap": $0.fastestLap]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
                let payload: [String: Any] = [
                    "driver": standing.driver.fullName,
                    "team": standing.teamName,
                    "position": standing.position,
                    "points": standing.points
                ]
                let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                return String(data: data, encoding: .utf8) ?? "{}"
            }
        )
    }

    /// 累计积分曲线数据点
    private func cumulativeData(_ rounds: [FEDriverRoundPoints]) -> [CumulativePoint] {
        var sum: Double = 0
        return rounds.map { e in
            sum += e.points
            return CumulativePoint(round: e.round, cumulative: sum)
        }
    }

    private struct CumulativePoint: Identifiable {
        let round: Int
        let cumulative: Double
        var id: Int { round }
    }
}
