import SwiftUI
import Charts

@MainActor
@Observable
final class WSSPRiderDetailViewModel {
    enum State {
        case idle
        case loading
        case loaded(rounds: [WSSPRiderRoundPoints])
        case failed(message: String)
    }

    let riderName: String           // standings 大写 fullname"JAUME MASIA"
    private(set) var state: State = .idle

    init(riderName: String) {
        self.riderName = riderName
    }

    private var lastName: String {
        riderName.split(separator: " ").last.map(String.init) ?? riderName
    }

    func load() async {
        state = .loading
        let rounds = await WSBKClient.shared.fetchSSPRiderRoundPoints(riderLastName: lastName)
        state = .loaded(rounds: rounds)
    }
}

struct WSSPRiderDetailView: View {
    @State private var viewModel: WSSPRiderDetailViewModel

    init(riderName: String) {
        _viewModel = State(initialValue: WSSPRiderDetailViewModel(riderName: riderName))
    }

    /// raw riderName 是大写"JAUME MASIA",中文模式走 mapping → "马西亚",英文模式 capitalize 美化。
    private var localizedRider: String {
        let mapped = MotorsportNames.driverFullName(rawFullName: viewModel.riderName, series: .wssp)
        // mapping 命中(中文)直接用;未命中(英文模式或没记录)走原 capitalize 兜底
        return mapped == viewModel.riderName ? viewModel.riderName.localizedCapitalized : mapped
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(localizedRider)
                        .font(.title2.weight(.semibold))
                    Text(L10n.t(zh: "WSSP 赛季", en: "WSSP Season"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            WikipediaSummarySection(queryTitle: viewModel.riderName.localizedCapitalized, series: .wssp)
            chartSection
            seasonReviewSection
            roundsSection
        }
        .dsDetailList()
        .navigationTitle(localizedRider)
        .navigationBarTitleDisplayMode(.inline)
        .tint(MotorsportSeries.wssp.brandColor)
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
                HStack { ProgressView(); Text(L10n.t(zh: "解析所有分站 PDF…", en: "Parsing round PDFs…")).foregroundStyle(.secondary) }
            }
        case .failed(let message):
            Section(L10n.t(zh: "累计积分", en: "Cumulative Points")) {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        case .loaded(let rounds):
            if rounds.isEmpty || rounds.allSatisfy({ $0.totalPoints == 0 }) {
                Section(L10n.t(zh: "累计积分", en: "Cumulative Points")) {
                    Text(L10n.t(zh: "赛季还没数据 / 该车手没出场", en: "No data yet / rider hasn't raced")).foregroundStyle(.secondary)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.roundName).font(.subheadline).lineLimit(1)
                            Text("Race 1: \(Int(entry.race1Points)) · Race 2: \(Int(entry.race2Points))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("+\(Int(entry.totalPoints))")
                            .font(DS.Font.numberMid)
                            .foregroundStyle(entry.totalPoints > 0 ? .primary : .tertiary)
                    }
                }
            }
        }
    }

    /// AI 赛季表现总结 — 仅 loaded(rounds non-empty) 时显示
    @ViewBuilder
    private var seasonReviewSection: some View {
        if case .loaded(let rounds) = viewModel.state,
           !rounds.isEmpty,
           !rounds.allSatisfy({ $0.totalPoints == 0 }) {
            DriverSeasonReviewSection(
                driverName: localizedRider,
                series: .wssp,
                dataProvider: { [rounds, name = localizedRider] in
                    let total = rounds.reduce(0.0) { $0 + $1.totalPoints }
                    let payload: [String: Any] = [
                        "driver": name,
                        "total_points": total,
                        "rounds": rounds.map {
                            [
                                "round": $0.round,
                                "name": $0.roundName,
                                "race1": $0.race1Points,
                                "race2": $0.race2Points,
                                "total": $0.totalPoints
                            ]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
            )
        }
    }

    private func cumulativeData(_ rounds: [WSSPRiderRoundPoints]) -> [CumulativePoint] {
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
