import SwiftUI

// MARK: - ViewModel

@MainActor
@Observable
final class MotoGPRoundDetailViewModel {
    enum SessionsState {
        case idle
        case loading
        case loaded(refs: [MotoGPSessionRef])
        case failed(message: String)
    }

    let round: MotoGPRound
    private(set) var sessionsState: SessionsState = .idle

    init(round: MotoGPRound) {
        self.round = round
    }

    func loadSessionsIfNeeded() async {
        guard case .idle = sessionsState else { return }
        sessionsState = .loading
        do {
            let refs = try await MotoGPClient.shared.fetchSessions(eventId: round.id)
            sessionsState = .loaded(refs: refs)
        } catch {
            sessionsState = .failed(message: error.localizedDescription)
        }
    }
}

// MARK: - View

struct MotoGPRoundDetailView: View {
    @State private var viewModel: MotoGPRoundDetailViewModel

    init(round: MotoGPRound) {
        _viewModel = State(initialValue: MotoGPRoundDetailViewModel(round: round))
    }

    var body: some View {
        List {
            headerSection
            recapSection
            circuitHighlightSection
            sessionsSection
        }
        .dsDetailList()
        .navigationTitle(viewModel.round.headline)
        .navigationBarTitleDisplayMode(.inline)
        .tint(MotorsportSeries.motogp.brandColor)
        .task { await viewModel.loadSessionsIfNeeded() }
        // navigationDestination 注册在 MotoGPRoundListView 的 NavigationStack 上,不在这里
    }

    /// AI 赛事概览 —— round 全部结束 + sessions 已加载 + 找到 race ref 时显示。
    @ViewBuilder
    private var recapSection: some View {
        if viewModel.round.currentStatus == .finished,
           case .loaded(let refs) = viewModel.sessionsState,
           let raceRef = refs.last(where: { $0.session.kind == .race }) {
            RaceRecapSection(
                eventKey: "motogp-\(viewModel.round.season)-\(viewModel.round.round)-race",
                series: .motogp,
                title: "\(viewModel.round.headline) · \(L10n.t(zh: "正赛", en: "Race"))",
                dataProvider: { [round = viewModel.round, raceRef] in
                    let results = (try? await MotoGPClient.shared.fetchSessionResults(
                        sessionId: raceRef.rawId
                    )) ?? []
                    let standings = (try? await MotoGPClient.shared.fetchRiderStandings()) ?? []
                    let payload: [String: Any] = [
                        "round": [
                            "season": round.season,
                            "round": round.round,
                            "name": round.name,
                            "circuit": round.circuit.name
                        ],
                        "results": results.prefix(15).map { r -> [String: Any] in
                            [
                                "pos": r.position,
                                "rider": r.rider.fullName,
                                "team": r.team.name,
                                "constructor": r.constructor.name,
                                "points": r.points,
                                "time_or_status": r.timeText ?? r.status,
                                "gap": r.gapToFirstText ?? ""
                            ]
                        },
                        "standings_top10": standings.prefix(10).map { s -> [String: Any] in
                            [
                                "pos": s.position,
                                "rider": s.rider.fullName,
                                "points": s.points,
                                "wins": s.raceWins
                            ]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
            )
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        Section {
            WeatherCard(
                location: viewModel.round.circuit.locality.isEmpty ? viewModel.round.circuit.country : viewModel.round.circuit.locality,
                targetDate: viewModel.round.weekendStart
            )
        }
    }

    /// AI 赛道亮点 — 放 recap 下方组成 AI 内容区
    @ViewBuilder
    private var circuitHighlightSection: some View {
        CircuitHighlightSection(
            series: .motogp,
            circuitName: viewModel.round.circuit.name,
            country: viewModel.round.circuit.country
        )
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
        case .loaded(let refs):
            // 按天分 Section,每个 session 独立 List row——不能用 VStack 包多 session 进同 cell
            ForEach(grouped(refs), id: \.0) { day, items in
                Section {
                    ForEach(items) { ref in
                        sessionRow(ref)
                    }
                } header: {
                    Text(day, format: .dateTime.weekday(.wide).month().day().beijing())
                        .textCase(nil)
                }
            }
        }
    }

    /// 已结束的 race / quali / sprint 行可点;练习不可点(MotoGP 练习 session 没有 classification)。
    @ViewBuilder
    private func sessionRow(_ ref: MotoGPSessionRef) -> some View {
        let finished = ref.session.startTime < Date()
        if finished, Self.supportsResults(kind: ref.session.kind) {
            NavigationLink(value: ref) {
                SessionRow(session: ref.session, finished: true, round: viewModel.round)
            }
        } else {
            SessionRow(session: ref.session, finished: false, round: viewModel.round)
        }
    }

    private static func supportsResults(kind: Session.Kind) -> Bool {
        switch kind {
        case .race, .qualifying, .sprint, .sprintShootout, .superpoleRace:
            return true
        case .practice:
            return false
        }
    }

    private func grouped(_ refs: [MotoGPSessionRef]) -> [(Date, [MotoGPSessionRef])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: refs) { calendar.startOfDay(for: $0.session.startTime) }
        return buckets.sorted { $0.key < $1.key }
    }
}

// MARK: - Row

private struct SessionRow: View {
    let session: Session
    let finished: Bool
    let round: MotoGPRound

    var body: some View {
        HStack {
            Text(session.label)
                .font(.subheadline.weight(.medium))
                .frame(width: 90, alignment: .leading)
            Text(session.startTime, format: .dateTime.hour().minute().beijing())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            kindBadge
            if !finished {
                CalendarToggleButton(
                    sessionKey: session.id,
                    title: "MotoGP \(round.headline) - \(session.label)",
                    start: session.startTime,
                    end: session.startTime.addingTimeInterval(session.defaultDuration),
                    notes: round.circuit.name
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
