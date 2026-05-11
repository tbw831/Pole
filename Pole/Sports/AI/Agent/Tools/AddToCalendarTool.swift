import Foundation

/// `add_to_calendar` —— 把某场比赛(可指定 sessions 类型)加入苹果日历。
/// EventKit 是 @MainActor,execute 内部 hop。
public struct AddToCalendarTool: AgentTool {
    public init() {}

    public let name = "add_to_calendar"
    public let description = """
    Add a race weekend to user's Apple Calendar (with 30-min reminder).
    Use when user asks to "save", "add to calendar", or "remind me" about a race.
    """
    public let parametersJSON = """
    {
      "type": "object",
      "properties": {
        "series": {"type": "string", "enum": ["f1", "motogp", "wsbk"]},
        "round": {"type": "integer"},
        "session_kinds": {
          "type": "array",
          "items": {"type": "string", "enum": ["race", "qualifying", "sprint", "all"]},
          "description": "Which sessions to add. Default: ['race']"
        }
      },
      "required": ["series", "round"],
      "additionalProperties": false
    }
    """

    /// `nonisolated` 让 Decodable conformance 在 nonisolated runningHint 里能 decode 不报警告。
    private nonisolated struct Args: Decodable {
        let series: String
        let round: Int
        let session_kinds: [String]?
    }

    public nonisolated func runningHint(argumentsJSON: String) -> String? {
        guard let args = try? JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8)) else {
            return L10n.t(zh: "加入日历…", en: "Adding to calendar…")
        }
        let series = args.series.uppercased()
        return L10n.t(
            zh: "把 \(series) 第 \(args.round) 站加入日历…",
            en: "Adding \(series) R\(args.round) to calendar…"
        )
    }

    public func execute(argumentsJSON: String) async throws -> String {
        let args = try JSONDecoder().decode(Args.self, from: Data(argumentsJSON.utf8))
        let kinds = args.session_kinds ?? ["race"]

        // 拿这一站的 sessions
        let sessions: [(label: String, start: Date, end: Date, headline: String, kind: Session.Kind)]
        switch args.series {
        case "f1":
            let races = (try? await JolpicaClient.shared.fetchSeasonRaces()) ?? []
            guard let race = races.first(where: { $0.round == args.round }) else {
                return #"{"error":"round not found"}"#
            }
            sessions = race.sessions.map { sess in
                (sess.localizedLabel, sess.startTime,
                 sess.startTime.addingTimeInterval(sess.defaultDuration),
                 race.raceName, sess.kind)
            }
        case "motogp":
            let rounds = (try? await MotoGPClient.shared.fetchSeasonRounds()) ?? []
            guard let round = rounds.first(where: { $0.round == args.round }) else {
                return #"{"error":"round not found"}"#
            }
            let refs = (try? await MotoGPClient.shared.fetchSessions(eventId: round.id)) ?? []
            sessions = refs.map { ref in
                (ref.session.localizedLabel, ref.session.startTime,
                 ref.session.startTime.addingTimeInterval(ref.session.defaultDuration),
                 round.headline, ref.session.kind)
            }
        case "wsbk":
            let rounds = (try? await WSBKClient.shared.fetchSeasonRounds()) ?? []
            guard let round = rounds.first(where: { $0.round == args.round }) else {
                return #"{"error":"round not found"}"#
            }
            let items = (try? await WSBKClient.shared.fetchEventSessions(
                countryCode: round.countryCode, year: round.season
            )) ?? []
            sessions = items.map { item in
                (item.session.localizedLabel, item.session.startTime,
                 item.session.startTime.addingTimeInterval(item.session.defaultDuration),
                 round.name, item.session.kind)
            }
        default:
            return #"{"error":"unknown series"}"#
        }

        // 过滤 kinds
        let wanted = kinds.contains("all") ? sessions : sessions.filter { sess in
            kinds.contains { kind in
                switch kind {
                case "race":       return sess.kind == .race || sess.kind == .superpoleRace
                case "qualifying": return sess.kind == .qualifying || sess.kind == .sprintShootout
                case "sprint":     return sess.kind == .sprint
                default:           return false
                }
            }
        }

        // 写入日历(MainActor)
        let seriesName = args.series.uppercased()
        var addedCount = 0
        for sess in wanted where sess.start > Date() {
            let title = "\(seriesName) \(sess.headline) - \(sess.label)"
            if let _ = await CalendarService.shared.addEvent(
                title: title, start: sess.start, end: sess.end, notes: nil
            ) {
                addedCount += 1
            }
        }
        let payload: [String: Any] = [
            "added_count": addedCount,
            "total_sessions": wanted.count,
            "filter_kinds": kinds
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
