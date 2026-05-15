import SwiftUI
import Combine
import PoleDesignSystem
import PoleDomain
import PoleMotorsportKit
import PoleUI

// MARK: - View

struct RaceDetailView: View {
    let race: F1Race
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true

    @State private var liveActivityStartCounter: Int = 0

    /// init 时算一次 — RaceDetailView 是 struct 但只在 navigation push 时重建,
    /// 不是每帧 body 重新 grouping(以前是 `var groupedSessions: [...] { ... }` 每次 body 重算)。
    private let groupedSessionsCached: [(Date, [Session])]

    init(race: F1Race) {
        self.race = race
        let calendar = Calendar.current
        let groups = Dictionary(grouping: race.sessions) { session in
            calendar.startOfDay(for: session.startTime)
        }
        self.groupedSessionsCached = groups.sorted { $0.key < $1.key }
    }

    var body: some View {
        List {
            heroSection
            headerSection
            recapSection               // 赛事概览(赛后才显示) — 放最上,AI 内容区主视觉
            circuitHighlightSection    // 赛道亮点 — 紧贴概览,AI 内容区视觉一致
            sessionsSection            // 时间表 — 移到 AI 区下方
            liveActivityToggleSection  // 高级功能下沉,不抢主视觉
        }
        .dsDetailList()
        .navigationTitle(race.headline)
        .navigationBarTitleDisplayMode(.inline)
        .tint(MotorsportSeries.f1.brandColor)
        .sensoryFeedback(.success, trigger: liveActivityStartCounter)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in }
        // 注:F1SessionResultsRef 的 navigationDestination 注册在 RaceListView 的
        // NavigationStack 上,不在这里——子 view 内部嵌套注册会让 SwiftUI 路径解析
        // 出现"返回时多出一层"的 bug。
    }

    /// "开始跟看 / 停止跟看"按钮 — 启停 Live Activity。
    /// 仅 weekendStart 在未来 8 小时内或正在进行时显示(超过 ActivityKit 限制启动会失败)。
    @ViewBuilder
    private var liveActivityToggleSection: some View {
        let now = Date()
        let inWindow = race.weekendEnd > now && race.weekendStart < now.addingTimeInterval(8 * 3600)
        if inWindow && liveActivityEnabled {
            Section {
                Button {
                    let entity = RaceAppEntity(
                        id: "f1:\(race.id)",
                        seriesRaw: "f1",
                        displayName: race.headline,
                        subtitle: race.subheadline,
                        startDate: race.weekendStart
                    )
                    _ = RaceLiveActivityCoordinator.shared.start(from: entity)
                    liveActivityStartCounter += 1   // 触发 success haptic
                } label: {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(MotorsportSeries.f1.brandColor)
                        Text(L10n.t(zh: "开始跟看(灵动岛 / 锁屏)",
                                    en: "Track on Dynamic Island / Lock Screen"))
                    }
                }
            }
        }
    }

    /// AI 赛事概览 —— 仅在比赛已结束时显示。
    @ViewBuilder
    private var recapSection: some View {
        if race.currentStatus == .finished {
            RaceRecapSection(
                eventKey: "f1-\(race.season)-\(race.round)-race",
                series: .f1,
                title: "\(race.headline) · \(L10n.t(zh: "正赛", en: "Race"))",
                dataProvider: { [race] in
                    let results = (try? await JolpicaClient.shared.fetchRaceResults(
                        season: race.season, round: race.round
                    )) ?? []
                    let standings = (try? await JolpicaClient.shared.fetchDriverStandings()) ?? []
                    let payload: [String: Any] = [
                        "race": [
                            "season": race.season,
                            "round": race.round,
                            "name": race.raceName,
                            "circuit": race.circuit.name,
                            "country": race.circuit.country
                        ],
                        "results": results.prefix(15).map { r -> [String: Any] in
                            var entry: [String: Any] = [
                                "pos": r.positionText,
                                "driver": r.driver.fullName,
                                "constructor": r.constructor.name,
                                "points": r.points,
                                "time_or_status": r.timeText ?? r.status
                            ]
                            if let fl = r.fastestLap {
                                entry["fastest_lap"] = fl.timeText
                                entry["fastest_lap_rank"] = fl.rank
                            }
                            return entry
                        },
                        "standings_top10": standings.prefix(10).map { s -> [String: Any] in
                            [
                                "pos": s.position,
                                "driver": s.driver.fullName,
                                "points": s.points,
                                "wins": s.wins
                            ]
                        }
                    ]
                    let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
                    return String(data: data, encoding: .utf8) ?? "{}"
                }
            )
            .dsHeroBanner(seriesAccent: MotorsportSeries.f1.brandColor)
        }
    }

    // MARK: Hero

    /// 顶部 hero:SeriesTopAccent 色条 + 站次/赛道名 + 可选倒计时起跑灯。
    @ViewBuilder
    private var heroSection: some View {
        Section {
            VStack(spacing: DS.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(race.headline)
                            .font(DS.Font.heroTitle)
                        Text(race.circuit.name)
                            .font(DS.Font.heroSubtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if race.currentStatus == .upcoming,
                   let startDate = race.mainRace?.startTime {
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
            .dsHeroBanner(seriesAccent: MotorsportSeries.f1.brandColor)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    // MARK: Header

    @ViewBuilder
    private var headerSection: some View {
        // 只保留天气;赛道亮点单独抽到 body 末尾,在赛事概览之后
        Section {
            WeatherCard(
                location: race.circuit.locality.isEmpty ? race.circuit.country : race.circuit.locality,
                targetDate: race.weekendStart
            )
        }
    }

    /// AI 赛道亮点 — 跟"赛事概览"视觉风格一致,放 recap 下方组成 AI 内容区
    @ViewBuilder
    private var circuitHighlightSection: some View {
        CircuitHighlightSection(
            series: .f1,
            circuitName: race.circuit.name,
            country: race.circuit.country
        )
    }

    // MARK: Sessions

    /// 按天分 Section,每个 session 独立 List row——不能用 VStack 包多 session 进同 cell,
    /// SwiftUI 会把整 cell 当一个 tap target 让"练习"行误触发邻近 NavigationLink 跳转。
    @ViewBuilder
    private var sessionsSection: some View {
        ForEach(groupedSessions, id: \.0) { day, sessions in
            Section {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            } header: {
                Text(day, format: .dateTime.weekday(.wide).month().day().beijing())
                    .textCase(nil)
            }
        }
    }

    /// 已结束的 race / 排位 / 冲刺行加 NavigationLink 进结果页;练习不可点。
    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let finished = session.startTime < Date()
        if finished, Self.supportsResults(kind: session.kind) {
            NavigationLink(value: F1SessionResultsRef(race: race, session: session)) {
                SessionRow(session: session, race: race)
            }
        } else {
            SessionRow(session: session, race: race)
        }
    }

    private static func supportsResults(kind: Session.Kind) -> Bool {
        switch kind {
        case .race, .qualifying, .sprint, .sprintShootout:
            return true
        case .practice, .superpoleRace:
            return false
        }
    }

    private var groupedSessions: [(Date, [Session])] {
        groupedSessionsCached
    }

}

// MARK: - Session Row

private struct SessionRow: View {
    let session: Session
    let race: F1Race

    var body: some View {
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
                    title: "F1 \(race.raceName) - \(session.localizedLabel)",
                    start: session.startTime,
                    end: session.startTime.addingTimeInterval(session.defaultDuration),
                    notes: race.circuit.name
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
