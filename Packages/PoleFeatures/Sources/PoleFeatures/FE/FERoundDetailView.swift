import SwiftUI
import Combine
import PoleDesignSystem
import PoleDomain
import PoleMotorsportKit
import PoleUI

@MainActor
@Observable
public final class FERoundDetailViewModel {
    enum SessionsState {
        case idle
        case loading
        case loaded(sessions: [FESession])
        case failed(message: String)
    }

    let rounds: [FERound]
    var selectedRoundIndex: Int
    private(set) var sessionsState: SessionsState = .idle

    var round: FERound { rounds[selectedRoundIndex] }
    var isDoubleHeader: Bool { rounds.count > 1 }
    var weekend: FEWeekend { FEWeekend(rounds: rounds) }

    public init(route: FERoute) {
        switch route {
        case .single(let r):
            self.rounds = [r]
            self.selectedRoundIndex = 0
        case .weekend(let w):
            self.rounds = w.rounds
            self.selectedRoundIndex = 0
        }
    }

    func loadSessions() async {
        sessionsState = .loading
        do {
            let sessions = try await FormulaEClient.shared.fetchSessions(raceId: round.id)
            sessionsState = .loaded(sessions: sessions)
        } catch {
            sessionsState = .failed(message: error.localizedDescription)
        }
    }
}

/// FE 单站详情——hero + 赛程时间表 + 完整成绩(汇总表)。
/// 双回合赛事头部显示 Race 切换。
public struct FERoundDetailView: View {
    @State private var viewModel: FERoundDetailViewModel

    public init(route: FERoute) {
        _viewModel = State(initialValue: FERoundDetailViewModel(route: route))
    }

    public var body: some View {
        List {
            heroSection
            if viewModel.isDoubleHeader {
                racePickerSection
            }
            headerSection
            recapSection
            circuitHighlightSection
            sessionsSection
            summarySection
        }
        .dsDetailList()
        .navigationTitle(viewModel.isDoubleHeader
            ? viewModel.weekend.headline
            : Localization.feRaceName(viewModel.round.name))
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(MotorsportSeries.fe.brandColor)
        .task { await viewModel.loadSessions() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in }
        // navigationDestination 注册在 outer NavigationStack 上,不在这里
    }

    /// 顶部 hero:SeriesTopAccent 色条 + 赛事名/赛道名 + 可选倒计时起跑灯。
    @ViewBuilder
    private var heroSection: some View {
        Section {
            VStack(spacing: DS.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(Localization.feRaceName(viewModel.round.name))
                            .font(DS.Font.heroTitle)
                        Text(viewModel.round.circuit.name)
                            .font(DS.Font.heroSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if viewModel.round.currentStatus == .upcoming {
                    let minutes = max(0, Int(viewModel.round.raceDate.timeIntervalSinceNow / 60))
                    if minutes <= 10 {
                        HStack {
                            Spacer()
                            StartLightGrid(mode: StartLightGrid.mode(forMinutesUntilStart: minutes), size: 16)
                            Spacer()
                        }
                        .padding(.top, DS.Spacing.sm)
                    }
                }
            }
            .padding(.vertical, DS.Spacing.sm)
            .dsHeroBanner(seriesAccent: MotorsportSeries.fe.brandColor)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// 双回合 Race 1 / Race 2 切换（用日期区分）
    @ViewBuilder
    private var racePickerSection: some View {
        Section {
            SegmentedPillPicker(
                selection: Binding(
                    get: { viewModel.selectedRoundIndex },
                    set: { newIndex in
                        guard newIndex != viewModel.selectedRoundIndex else { return }
                        viewModel.selectedRoundIndex = newIndex
                        Task { await viewModel.loadSessions() }
                    }
                ),
                items: Array(viewModel.rounds.indices),
                label: { index in
                    let round = viewModel.rounds[index]
                    Text(round.raceDate, format: .dateTime.month(.abbreviated).day().beijing())
                }
            )
        }
    }

    /// AI 赛事概览 — round 已结束时显示。dataProvider 给 LLM 当前 standings + round info。
    @ViewBuilder
    private var recapSection: some View {
        if viewModel.round.currentStatus == .finished {
            RaceRecapSection(
                eventKey: "fe-\(viewModel.round.season)-\(viewModel.round.round)-recap",
                series: .fe,
                title: "\(viewModel.round.headline) · \(L10n.t(zh: "赛后", en: "Recap"))",
                dataProvider: { [round = viewModel.round] in
                    let standings = (try? await FormulaEClient.shared.fetchDriverStandings()) ?? []
                    let payload: [String: Any] = [
                        "series": "Formula E",
                        "round": [
                            "season": round.season,
                            "round": round.round,
                            "name": round.name,
                            "circuit": round.circuit.name,
                            "locality": round.circuit.locality,
                            "country": round.circuit.country
                        ],
                        "standings_top10": standings.prefix(10).map { s -> [String: Any] in
                            [
                                "pos": s.position,
                                "driver": s.driver.fullName,
                                "team": s.teamName,
                                "points": s.points
                            ]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
            )
            .dsHeroBanner(seriesAccent: MotorsportSeries.fe.brandColor)
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            WeatherCard(
                location: viewModel.round.circuit.locality.isEmpty
                    ? viewModel.round.circuit.country
                    : viewModel.round.circuit.locality,
                targetDate: viewModel.round.weekendStart
            )
        }
    }

    /// AI 赛道亮点 — 放 recap 下方组成 AI 内容区
    @ViewBuilder
    private var circuitHighlightSection: some View {
        CircuitHighlightSection(
            series: .fe,
            circuitName: viewModel.round.circuit.name,
            country: viewModel.round.circuit.country
        )
    }

    /// 真实赛场 session（按时间升序）
    @ViewBuilder
    private var sessionsSection: some View {
        switch viewModel.sessionsState {
        case .idle, .loading:
            Section(L10n.t(zh: "赛程", en: "Schedule")) {
                HStack { ProgressView(); Text(L10n.t(zh: "加载赛程…", en: "Loading sessions…")).foregroundStyle(.secondary) }
            }
        case .failed(let message):
            Section(L10n.t(zh: "赛程", en: "Schedule")) {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        case .loaded(let all):
            let real = all.filter { !$0.isSummary }
                .sorted { $0.startTime < $1.startTime }
            if !real.isEmpty {
                Section(L10n.t(zh: "赛程", en: "Schedule")) {
                    ForEach(real) { sessionRow($0) }
                }
            }
        }
    }

    /// 派生汇总表(Combined qualifying / Starting grid / Fastest lap / Qualifying grid)
    @ViewBuilder
    private var summarySection: some View {
        if case .loaded(let all) = viewModel.sessionsState {
            let summary = all.filter { $0.isSummary }
            if !summary.isEmpty {
                Section(L10n.t(zh: "完整成绩", en: "Full Results")) {
                    ForEach(summary) { sessionRow($0) }
                }
            }
        }
    }

    /// 已结束 + 有 results 的 session 加 NavigationLink。
    @ViewBuilder
    private func sessionRow(_ session: FESession) -> some View {
        if session.hasResults {
            NavigationLink(value: FESessionRef(round: viewModel.round, session: session)) {
                FESessionRow(round: viewModel.round, session: session)
            }
        } else {
            FESessionRow(round: viewModel.round, session: session)
        }
    }
}

private struct FESessionRow: View {
    let round: FERound
    let session: FESession

    public var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(session.localizedDisplayName.uppercased())
                .font(DS.Font.heroSubtitle.weight(.heavy))
                .tracking(0.5)
                // FE labels longer than other series (e.g. "COMBINED QUALIFYING"), needs wider column
                .frame(width: 130, alignment: .leading)
            if !session.isSummary {
                Text(session.startTime)
                    .font(DS.Font.numberSmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            kindBadge
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        switch session.kind {
        case .race:       badge(L10n.t(zh: "正赛", en: "Race"), color: .red)
        case .qualifying: badge(L10n.t(zh: "排位", en: "Quali"), color: .blue)
        case .practice:   badge(L10n.t(zh: "练习", en: "Practice"), color: .gray)
        case .summary:    badge(L10n.t(zh: "汇总", en: "Summary"), color: .indigo)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
}
