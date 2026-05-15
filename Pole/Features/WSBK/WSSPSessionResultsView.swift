import SwiftUI
import PoleDesignSystem
import PoleDomain
import PoleMotorsportKit

@MainActor
@Observable
final class WSSPSessionResultsViewModel {
    enum State {
        case idle
        case loading
        case loaded(rows: [WSSPRaceResult])
        case failed(message: String)
    }

    let item: WSSPSessionWithResults
    private(set) var state: State = .idle

    init(item: WSSPSessionWithResults) {
        self.item = item
    }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        guard let url = item.resultsPdfURL else {
            state = .failed(message: L10n.t(zh: "暂无结果数据", en: "No results available"))
            return
        }
        state = .loading
        do {
            let rows = try await WSBKClient.shared.fetchSSPSessionResults(pdfURL: url)
            state = .loaded(rows: rows)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}

struct WSSPSessionResultsView: View {
    @State private var viewModel: WSSPSessionResultsViewModel

    init(item: WSSPSessionWithResults) {
        _viewModel = State(initialValue: WSSPSessionResultsViewModel(item: item))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.item.session.localizedLabel)
            .navigationBarTitleDisplayMode(.inline)
            .tint(MotorsportSeries.wssp.brandColor)
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView(L10n.t(zh: "解析 PDF…", en: "Parsing PDF…"))
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
    let row: WSSPRaceResult

    private var isP1: Bool { row.position == 1 }

    var body: some View {
        HStack(spacing: 10) {
            positionBadge
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayRiderName).font(.subheadline.weight(.medium))
                    Text("#\(row.number)").font(.caption2.bold()).foregroundStyle(.secondary)
                }
                Text(row.displayTeam).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.timeText ?? "—")
                    .font(DS.Font.numberSmall)
                if let gap = row.gapText {
                    Text("+\(gap)")
                        .font(DS.Font.numberSmall)
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
}
