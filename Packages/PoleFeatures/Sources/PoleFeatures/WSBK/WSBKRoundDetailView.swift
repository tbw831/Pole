import SwiftUI
import Combine
import PoleDesignSystem
import PoleDomain
import PoleMotorsportKit
import PoleUI

@MainActor
@Observable
public final class WSBKRoundDetailViewModel {
    enum SessionsState {
        case idle
        case loading
        case loaded(items: [WSSPSessionWithResults])
        case failed(message: String)
    }

    let round: WSBKRound
    private(set) var sessionsState: SessionsState = .idle

    public init(round: WSBKRound) {
        self.round = round
    }

    func loadSessionsIfNeeded() async {
        guard case .idle = sessionsState else { return }
        sessionsState = .loading
        do {
            let items = try await WSBKClient.shared.fetchEventSessions(
                countryCode: round.countryCode,
                year: round.season
            )
            sessionsState = .loaded(items: items)
        } catch {
            sessionsState = .failed(message: error.localizedDescription)
        }
    }
}

public struct WSBKRoundDetailView: View {
    @State private var viewModel: WSBKRoundDetailViewModel

    public init(round: WSBKRound) {
        _viewModel = State(initialValue: WSBKRoundDetailViewModel(round: round))
    }

    public var body: some View {
        List {
            heroSection
            headerSection
            recapSection
            circuitHighlightSection
            sessionsSection
        }
        .dsDetailList()
        .navigationTitle(viewModel.round.headline)
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(MotorsportSeries.wssp.brandColor)
        .task { await viewModel.loadSessionsIfNeeded() }
        // navigationDestination 注册在 WSBKRoundListView 的 NavigationStack 上,不在这里
    }

    /// 顶部 hero:SeriesTopAccent 色条 + 站次/赛道名 + 可选倒计时起跑灯。
    @ViewBuilder
    private var heroSection: some View {
        Section {
            VStack(spacing: DS.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(viewModel.round.headline)
                            .font(DS.Font.heroTitle)
                        Text(viewModel.round.circuit.name)
                            .font(DS.Font.heroSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if viewModel.round.currentStatus == .upcoming,
                   let startDate = viewModel.round.mainRace?.startTime {
                    let minutes = max(0, Int(startDate.timeIntervalSinceNow / 60))
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
            .dsHeroBanner(seriesAccent: MotorsportSeries.wssp.brandColor)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// AI 赛事概览 — round 已结束时显示。dataProvider 给 LLM 当前 standings + round info。
    @ViewBuilder
    private var recapSection: some View {
        if viewModel.round.currentStatus == .finished {
            RaceRecapSection(
                eventKey: "wssp-\(viewModel.round.season)-\(viewModel.round.round)-recap",
                series: .wssp,
                title: "\(viewModel.round.headline) · \(L10n.t(zh: "赛后", en: "Recap"))",
                dataProvider: { [round = viewModel.round] in
                    let standings = (try? await WSBKClient.shared.fetchSSPRiderStandings()) ?? []
                    let payload: [String: Any] = [
                        "series": "WorldSSP",
                        "round": [
                            "season": round.season,
                            "round": round.round,
                            "name": round.name,
                            "circuit": round.circuit.name,
                            "country": round.countryCode
                        ],
                        "standings_top10": standings.prefix(10).map { s -> [String: Any] in
                            [
                                "pos": s.position,
                                "rider": s.rider.fullName,
                                "points": s.points,
                                "wins": s.wins
                            ]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
            )
            .dsHeroBanner(seriesAccent: MotorsportSeries.wssp.brandColor)
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            WeatherCard(
                location: viewModel.round.countryCode,
                targetDate: viewModel.round.weekendStart
            )
        }
    }

    /// AI 赛道亮点 — 放 recap 下方组成 AI 内容区
    @ViewBuilder
    private var circuitHighlightSection: some View {
        CircuitHighlightSection(
            series: .wssp,
            circuitName: viewModel.round.circuit.name,
            country: viewModel.round.countryCode
        )
    }

    /// 北京时间下的周末日期范围。
    private var formattedDateRange: String {
        let start = viewModel.round.dateStart.formatted(.dateTime.month(.abbreviated).day().beijing())
        let end = viewModel.round.dateEnd.formatted(.dateTime.month(.abbreviated).day().beijing())
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private var sessionsSection: some View {
        switch viewModel.sessionsState {
        case .idle, .loading:
            Section(L10n.t(zh: "赛程", en: "Schedule")) {
                HStack {
                    ProgressView()
                    Text(L10n.t(zh: "加载赛程…", en: "Loading sessions…"))
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Section(L10n.t(zh: "赛程", en: "Schedule")) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .loaded(let items):
            // 按天分 Section,每个 session 独立 List row
            ForEach(grouped(items), id: \.0) { day, dayItems in
                Section {
                    ForEach(dayItems) { item in
                        sessionRow(item)
                    }
                } header: {
                    Text(day, format: .dateTime.weekday(.wide).month().day().beijing())
                        .textCase(nil)
                }
            }
        }
    }

    /// 已结束且有 PDF 的 race/quali/sprint 用 NavigationLink 进结果页。
    @ViewBuilder
    private func sessionRow(_ item: WSSPSessionWithResults) -> some View {
        if item.resultsPdfURL != nil, Self.supportsResults(kind: item.session.kind) {
            NavigationLink(value: item) {
                SessionRow(item: item, round: viewModel.round)
            }
        } else {
            SessionRow(item: item, round: viewModel.round)
        }
    }

    private static func supportsResults(kind: Session.Kind) -> Bool {
        switch kind {
        case .race, .superpoleRace, .qualifying, .sprint, .sprintShootout:
            return true
        case .practice:
            return false
        }
    }

    private func grouped(_ items: [WSSPSessionWithResults]) -> [(Date, [WSSPSessionWithResults])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: items) { calendar.startOfDay(for: $0.session.startTime) }
        return buckets.sorted { $0.key < $1.key }
    }
}

private struct SessionRow: View {
    let item: WSSPSessionWithResults
    let round: WSBKRound

    private var session: Session { item.session }

    public var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(session.localizedLabel.uppercased())
                .font(DS.Font.heroSubtitle.weight(.heavy))
                .tracking(0.5)
                .frame(width: 100, alignment: .leading)
            Text(session.startTime, format: .dateTime.hour().minute().beijing())
                .font(DS.Font.numberSmall)
                .foregroundStyle(.secondary)
            Spacer()
            kindBadge
            if session.startTime > Date() {
                CalendarToggleButton(
                    sessionKey: session.id,
                    title: "WSBK \(round.name) - \(session.localizedLabel)",
                    start: session.startTime,
                    end: session.startTime.addingTimeInterval(session.defaultDuration),
                    notes: round.countryCode
                )
            }
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        let color: Color = {
            switch session.kind {
            case .race:           return .red
            case .sprint:         return .purple
            case .superpoleRace:  return .pink
            case .qualifying:     return .blue
            case .sprintShootout: return .indigo
            case .practice:       return .gray
            }
        }()
        badge(session.kind.displayLabel, color: color)
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
