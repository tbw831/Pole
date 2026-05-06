import SwiftUI
import SwiftData

/// 单个 FollowTarget 的关注开关。每个 button 用 @Query 监听自己的 key,
/// SwiftData 写入后会自动重渲染。在 List 行里安全使用。
struct FollowToggleButton: View {
    let target: FollowTarget
    let displayName: String

    @Environment(\.modelContext) private var context
    @Query private var matches: [FollowedItem]

    init(target: FollowTarget, displayName: String) {
        self.target = target
        self.displayName = displayName
        let key = FollowedItem.makeKey(target)
        _matches = Query(filter: #Predicate<FollowedItem> { $0.key == key })
    }

    private var isFollowed: Bool { !matches.isEmpty }

    @State private var bumpedAt: Date = .distantPast

    var body: some View {
        Button {
            FollowStore(context: context).toggle(target, displayName: displayName)
            bumpedAt = .now   // 触发 scale bounce 动画
        } label: {
            Image(systemName: isFollowed ? "star.fill" : "star")
                .foregroundStyle(isFollowed ? .yellow : .secondary)
                .font(.body)
                .scaleEffect(isFollowed ? 1.05 : 1.0)
                .symbolEffect(.bounce, value: bumpedAt)
                .animation(.spring(response: 0.32, dampingFraction: 0.55), value: isFollowed)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isFollowed
                            ? L10n.t(zh: "取消关注", en: "Unfollow")
                            : L10n.t(zh: "关注", en: "Follow"))
        // 关注时 success(双段强 haptic),取消时 warning(单段轻 haptic),反馈不同动作
        .sensoryFeedback(isFollowed ? .success : .warning, trigger: bumpedAt)
        .contentTransition(.symbolEffect(.replace))
    }
}
