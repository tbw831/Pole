import SwiftUI
import Charts

@MainActor
@Observable
final class F1DriverDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(rounds: [F1DriverRoundPoints])
        case failed(message: String)
    }

    let driverId: String
    let driverName: String
    let season: String
    private(set) var state: State = .idle

    init(driverId: String, driverName: String, season: String) {
        self.driverId = driverId
        self.driverName = driverName
        self.season = season
    }

    func load() async {
        state = .loading
        do {
            let rounds = try await JolpicaClient.shared.fetchDriverSeasonResults(
                season: season,
                driverId: driverId
            )
            state = .loaded(rounds: rounds)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

struct F1DriverDetailView: View {
    @State private var viewModel: F1DriverDetailViewModel

    init(driverId: String, driverName: String, season: String) {
        _viewModel = State(initialValue: F1DriverDetailViewModel(
            driverId: driverId, driverName: driverName, season: season
        ))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MotorsportNames.driverFullName(rawFullName: viewModel.driverName, series: .f1))
                        .font(.title2.weight(.semibold))
                    Text(L10n.t(zh: "F1 \(viewModel.season) 赛季", en: "F1 \(viewModel.season) Season"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            WikipediaSummarySection(queryTitle: viewModel.driverName, series: .f1)
            chartSection
            seasonReviewSection
            roundsSection
        }
        .dsDetailList()
        .navigationTitle(MotorsportNames.driverFullName(rawFullName: viewModel.driverName, series: .f1))
        .navigationBarTitleDisplayMode(.inline)
        .tint(MotorsportSeries.f1.brandColor)
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
                ForEach(rounds, id: \.round) { entry in
                    HStack(spacing: DS.Spacing.sm) {
                        Text("R\(entry.round)")
                            .font(DS.Font.numberSmall)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        Text(entry.raceName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("+\(entry.points, format: .number)")
                            .font(DS.Font.numberMid)
                            .foregroundStyle(entry.points > 0 ? .primary : .tertiary)
                    }
                }
            }
        }
    }

    /// AI 赛季表现总结 — 仅 loaded(rounds non-empty) 时显示
    @ViewBuilder
    private var seasonReviewSection: some View {
        if case .loaded(let rounds) = viewModel.state, !rounds.isEmpty {
            DriverSeasonReviewSection(
                driverName: viewModel.driverName,
                series: .f1,
                dataProvider: { [rounds, season = viewModel.season, name = viewModel.driverName] in
                    let total = rounds.reduce(0.0) { $0 + $1.points }
                    let payload: [String: Any] = [
                        "driver": name,
                        "season": season,
                        "total_points": total,
                        "rounds": rounds.map {
                            ["round": $0.round, "race": $0.raceName, "points": $0.points]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
            )
        }
    }

    /// 累计积分曲线数据点
    private func cumulativeData(_ rounds: [F1DriverRoundPoints]) -> [CumulativePoint] {
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
