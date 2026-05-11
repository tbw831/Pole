import SwiftUI

@MainActor
@Observable
final class F1SessionResultsViewModel {
    enum State {
        case idle
        case loading
        case loadedRace(rows: [F1RaceResult])
        case loadedQualifying(rows: [F1QualifyingResult])
        case failed(message: String)
    }

    let ref: F1SessionResultsRef
    private(set) var state: State = .idle

    init(ref: F1SessionResultsRef) {
        self.ref = ref
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        state = .loading
        let client = JolpicaClient.shared
        do {
            switch ref.session.kind {
            case .race:
                let rows = try await client.fetchRaceResults(season: ref.race.season, round: ref.race.round)
                state = .loadedRace(rows: rows)
            case .sprint:
                let rows = try await client.fetchSprintResults(season: ref.race.season, round: ref.race.round)
                state = .loadedRace(rows: rows)
            case .qualifying, .sprintShootout:
                let rows = try await client.fetchQualifyingResults(season: ref.race.season, round: ref.race.round)
                state = .loadedQualifying(rows: rows)
            case .practice, .superpoleRace:
                state = .failed(message: L10n.t(zh: "该 session 暂无结果", en: "No results for this session"))
            }
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

struct F1SessionResultsView: View {
    @State private var viewModel: F1SessionResultsViewModel

    init(ref: F1SessionResultsRef) {
        _viewModel = State(initialValue: F1SessionResultsViewModel(ref: ref))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.ref.session.label)
            .navigationBarTitleDisplayMode(.inline)
            .tint(MotorsportSeries.f1.brandColor)
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载…", en: "Loading…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loadedRace(let rows):
            if rows.isEmpty {
                ContentUnavailableView(L10n.t(zh: "暂无结果", en: "No Results"), systemImage: "list.bullet.rectangle")
            } else {
                List(rows) { RaceResultRow(result: $0) }.listStyle(.plain)
            }
        case .loadedQualifying(let rows):
            if rows.isEmpty {
                ContentUnavailableView(L10n.t(zh: "暂无结果", en: "No Results"), systemImage: "list.bullet.rectangle")
            } else {
                List(rows) { QualifyingResultRow(result: $0) }.listStyle(.plain)
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.loadIfNeeded() } }
        }
    }
}

// MARK: - Rows

private struct RaceResultRow: View {
    let result: F1RaceResult

    private var isP1: Bool { result.positionText == "1" }

    var body: some View {
        HStack(spacing: 10) {
            positionLabel
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.driver.displayName).font(.subheadline.weight(.medium))
                    if let n = result.driver.permanentNumber {
                        Text("#\(n)").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Text(result.constructor.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let timeText = result.timeText {
                    Text(timeText).font(DS.Font.numberSmall)
                } else {
                    Text(result.status).font(.caption).foregroundStyle(.secondary)
                }
                if result.points > 0 {
                    Text("+\(result.points, format: .number) \(L10n.t(zh: "分", en: "pts"))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .listRowBackground(isP1 ? DS.Palette.racingRedFaint : Color.clear)
    }

    @ViewBuilder
    private var positionLabel: some View {
        let text = result.positionText
        let isNumeric = Int(text) != nil
        Text(text)
            .font(DS.Font.numberMid)
            .foregroundStyle(isP1 ? DS.Palette.racingRed : (isNumeric ? .primary : .secondary))
            .frame(width: 28, alignment: .center)
    }
}

private struct QualifyingResultRow: View {
    let result: F1QualifyingResult

    private var isP1: Bool { result.position == 1 }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(result.position)")
                .font(DS.Font.numberMid)
                .foregroundStyle(isP1 ? DS.Palette.racingRed : .primary)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.driver.displayName).font(.subheadline.weight(.medium))
                    if let n = result.driver.permanentNumber {
                        Text("#\(n)").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Text(result.constructor.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(bestTime ?? "—")
                .font(DS.Font.numberSmall)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(isP1 ? DS.Palette.racingRedFaint : Color.clear)
    }

    private var bestTime: String? {
        result.q3 ?? result.q2 ?? result.q1
    }
}
