import SwiftUI
import PoleDesignSystem
import PoleDomain

@MainActor
@Observable
final class MotoGPSessionResultsViewModel {
    enum State {
        case idle
        case loading
        case loaded(rows: [MotoGPRaceResult])
        case failed(message: String)
    }

    let ref: MotoGPSessionRef
    private(set) var state: State = .idle

    init(ref: MotoGPSessionRef) {
        self.ref = ref
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        state = .loading
        do {
            let rows = try await MotoGPClient.shared.fetchSessionResults(sessionId: ref.rawId)
            state = .loaded(rows: rows)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

struct MotoGPSessionResultsView: View {
    @State private var viewModel: MotoGPSessionResultsViewModel

    init(ref: MotoGPSessionRef) {
        _viewModel = State(initialValue: MotoGPSessionResultsViewModel(ref: ref))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.ref.session.localizedLabel)
            .navigationBarTitleDisplayMode(.inline)
            .tint(MotorsportSeries.motogp.brandColor)
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "加载结果…", en: "Loading results…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let rows):
            if rows.isEmpty {
                ContentUnavailableView(L10n.t(zh: "暂无结果", en: "No Results"), systemImage: "list.bullet.rectangle")
            } else {
                List(rows) { ResultRow(row: $0) }
                    .listStyle(.plain)
            }
        case .failed(let message):
            ErrorView(message: message) { Task { await viewModel.loadIfNeeded() } }
        }
    }
}

private struct ResultRow: View {
    let row: MotoGPRaceResult

    private var isP1: Bool { row.position == 1 }

    var body: some View {
        HStack(spacing: 10) {
            positionBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.rider.displayName).font(.subheadline.weight(.medium))
                    if let n = row.rider.number {
                        Text("#\(n)").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Text("\(row.team.displayName) · \(row.constructor.displayName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(timingText)
                    .font(DS.Font.numberSmall)
                    .foregroundStyle(timingColor)
                if row.points > 0 {
                    Text("+\(Int(row.points)) \(L10n.t(zh: "分", en: "pts"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listRowBackground(isP1 ? DS.Palette.racingRedFaint : Color.clear)
    }

    private var positionBadge: some View {
        Text("\(row.position)")
            .font(DS.Font.numberMid)
            .foregroundStyle(isP1 ? DS.Palette.racingRed : (row.position <= 3 ? .primary : .secondary))
            .frame(width: 28, alignment: .center)
    }

    /// 主时间显示:领先者用总时间,其他人用 +gap;非完赛(NDC/NOSUM 等)用 status。
    private var timingText: String {
        if let gap = row.gapToFirstText { return gap }
        if let t = row.timeText, !t.isEmpty { return t }
        return row.status
    }

    private var timingColor: Color {
        (row.timeText != nil || row.gapToFirstText != nil) ? .primary : .secondary
    }
}
