import SwiftUI
import SwiftData
import PoleDesignSystem

/// 历史会话列表——从 sheet 弹出。
/// - 默认模式：点击切换会话，左滑单条删除
/// - "选择"模式：左侧圆圈选中 + 顶 bar"删除"批量清理（用户诉求）
struct ChatHistoryView: View {
    @Query(sort: \ChatSession.lastUpdatedAt, order: .reverse) private var sessions: [ChatSession]
    let currentSessionID: UUID?
    let onSelect: (ChatSession) -> Void
    let onDelete: (ChatSession) -> Void
    let onNew: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<UUID> = []
    /// 待二次确认的单条删除目标 — 非 nil 时弹 confirmationDialog。
    @State private var pendingDeleteSession: ChatSession?
    /// 待二次确认的批量删除 flag — 删除前弹 confirmationDialog。
    @State private var showBatchDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        L10n.t(zh: "还没有历史对话", en: "No chat history yet"),
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(L10n.t(zh: "发条消息开启第一段对话",
                                                 en: "Send a message to start your first chat"))
                    )
                } else {
                    List(selection: $selectedIDs) {
                        ForEach(sessions, id: \.id) { s in
                            row(s)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // 仅默认模式下 tap = 切换会话;选择模式由 List(selection:) 内部处理
                                    if editMode == .inactive {
                                        onSelect(s)
                                        dismiss()
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    // 默认模式左滑单条删;用 .swipeActions 而非 .onDelete,
                                    // 避免选择模式左侧出现多余的 "−" 圆形按钮(SwiftUI 默认行为)。
                                    // 不直接 onDelete,先弹 confirmationDialog 二次确认。
                                    Button(role: .destructive) {
                                        pendingDeleteSession = s
                                    } label: {
                                        Label(L10n.t(zh: "删除", en: "Delete"),
                                              systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .dsDetailList()
                    .environment(\.editMode, $editMode)
                }
            }
            .navigationTitle(L10n.t(zh: "历史对话", en: "History"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            // 单条删除二次确认 — title 含会话名,destructive button + Cancel
            .confirmationDialog(
                pendingDeleteSession.map { sessionTitle($0) } ?? "",
                isPresented: Binding(
                    get: { pendingDeleteSession != nil },
                    set: { if !$0 { pendingDeleteSession = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.t(zh: "删除", en: "Delete"), role: .destructive) {
                    if let s = pendingDeleteSession { onDelete(s) }
                    pendingDeleteSession = nil
                }
                Button(L10n.t(zh: "取消", en: "Cancel"), role: .cancel) {
                    pendingDeleteSession = nil
                }
            } message: {
                Text(L10n.t(zh: "确定要删除这条对话吗?删除后无法恢复。",
                            en: "Delete this chat? This cannot be undone."))
            }
            // 批量删除二次确认 — 显示选中数量
            .confirmationDialog(
                L10n.t(zh: "删除 \(selectedIDs.count) 条对话",
                       en: "Delete \(selectedIDs.count) chats"),
                isPresented: $showBatchDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(L10n.t(zh: "删除", en: "Delete"), role: .destructive) {
                    deleteSelected()
                }
                Button(L10n.t(zh: "取消", en: "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t(zh: "选中的对话将永久删除,无法恢复。",
                            en: "Selected chats will be permanently deleted."))
            }
        }
    }

    /// 格式化 session title 给 confirmationDialog 当 visibility title 用。
    private func sessionTitle(_ s: ChatSession) -> String {
        s.title.isEmpty
            ? L10n.t(zh: "删除该对话", en: "Delete chat")
            : L10n.t(zh: "删除「\(s.title)」", en: "Delete \"\(s.title)\"")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if editMode == .active {
            // 选择模式：左"取消"，右"删除选中(N)"
            ToolbarItem(placement: .topBarLeading) {
                Button(L10n.t(zh: "取消", en: "Cancel")) {
                    editMode = .inactive
                    selectedIDs.removeAll()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    // 不直接 deleteSelected,先弹 confirmationDialog 二次确认
                    showBatchDeleteConfirm = true
                } label: {
                    Text(selectedIDs.isEmpty
                         ? L10n.t(zh: "删除", en: "Delete")
                         : L10n.t(zh: "删除(\(selectedIDs.count))", en: "Delete (\(selectedIDs.count))"))
                }
                .disabled(selectedIDs.isEmpty)
                .tint(.red)
            }
        } else {
            // 默认模式：左"关闭"，右"选择"。新建按钮删除（点"关闭"回主页本身就能新建）
            ToolbarItem(placement: .topBarLeading) {
                Button(L10n.t(zh: "关闭", en: "Close")) { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editMode = .active
                    selectedIDs.removeAll()
                } label: {
                    Text(L10n.t(zh: "选择", en: "Select"))
                        .font(.subheadline)
                }
                .disabled(sessions.isEmpty)
            }
        }
    }

    private func deleteSelected() {
        for id in selectedIDs {
            if let s = sessions.first(where: { $0.id == id }) {
                onDelete(s)
            }
        }
        selectedIDs.removeAll()
        editMode = .inactive
    }

    @ViewBuilder
    private func row(_ s: ChatSession) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title.isEmpty ? L10n.t(zh: "新对话", en: "New Chat") : s.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(s.lastUpdatedAt, format: .relative(presentation: .named))
                    Text("·")
                    Text(L10n.t(zh: "\(s.messages.count) 条", en: "\(s.messages.count) msg"))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            // 选择模式下不显示 currentSessionID 对勾，避免跟左侧 selection 圆圈冲突
            if editMode == .inactive, s.id == currentSessionID {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}
