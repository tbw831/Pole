import SwiftUI
import SwiftData

struct ContentView: View {
    /// 监听语言切换 — 切换时整体 .id(languageRaw) 重建子树,所有 L10n.t 文案立即刷新。
    @AppStorage("languageMode") private var languageRaw: String = LanguageMode.zh.rawValue
    @State private var selection: AppTab = .motorsport

    enum AppTab: String, CaseIterable, Identifiable {
        case motorsport, standings, ai, follow, settings
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .motorsport: return "flag.checkered"
            case .standings:  return "list.number"
            case .ai:         return "bolt.car.fill"
            case .follow:     return "star"
            case .settings:   return "gearshape"
            }
        }
        var label: String {
            switch self {
            case .motorsport: return L10n.t(zh: "赛历", en: "Calendar")
            case .standings:  return L10n.t(zh: "积分榜", en: "Standings")
            // 助手昵称"小赛"——对话亲切感比"赛车助手"高;英文用拼音 Xiao Sai 保持品牌一致
            case .ai:         return L10n.t(zh: "小赛", en: "Xiao Sai")
            case .follow:     return L10n.t(zh: "关注", en: "Follow")
            case .settings:   return L10n.t(zh: "设置", en: "Settings")
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            // 用 Tab(value:){content}label:{} 形式,label 内自定义 Image 加 .imageScale(.small),
            // 让所有 tab 图标比系统默认的 medium 小一档,视觉更精致。
            // (Tab(_:systemImage:value:) 直接传字符串无法接 modifier,系统自己 sizing。)
            Tab(value: AppTab.motorsport) {
                MotorsportListView()
            } label: {
                Label { Text(AppTab.motorsport.label) }
                icon: { Image(systemName: AppTab.motorsport.icon).imageScale(.small) }
            }
            Tab(value: AppTab.standings) {
                StandingsView()
            } label: {
                Label { Text(AppTab.standings.label) }
                icon: { Image(systemName: AppTab.standings.icon).imageScale(.small) }
            }
            Tab(value: AppTab.ai) {
                ChatView()
            } label: {
                // 注意:iOS 26 系统 Tab Bar 的 icon 必须是 Image(SF Symbol / Asset),
                // 不接受任意 SwiftUI View(ZStack/Text 不会 render)。
                // 自定义"AI 两字"图标需要往 Assets.xcassets 加 AITabIcon image set,
                // 然后这里换成 Image("AITabIcon").renderingMode(.template)。
                Label { Text(AppTab.ai.label) }
                icon: { Image(systemName: AppTab.ai.icon).imageScale(.small) }
            }
            Tab(value: AppTab.follow) {
                FollowFeedView()
            } label: {
                Label { Text(AppTab.follow.label) }
                icon: { Image(systemName: AppTab.follow.icon).imageScale(.small) }
            }
            Tab(value: AppTab.settings) {
                SettingsView()
            } label: {
                Label { Text(AppTab.settings.label) }
                icon: { Image(systemName: AppTab.settings.icon).imageScale(.small) }
            }
        }
        // iOS 26+ 系统 Liquid Glass tab bar + 滚动时收缩
        .tabBarMinimizeBehavior(.onScrollDown)
        // 不再硬染红色,走系统 accent(可被 Asset Catalog AccentColor 配置)
        // 系列识别仍由各 view 内 `series.brandColor` 局部染色保留
        .id(languageRaw)   // 切语言整树重建,所有 L10n.t 立即刷新
        .onChange(of: selection) { _, newTab in
            // 每次切到 AI tab 都让 ChatView 回 starter(greeting),不延续上次会话
            if newTab == .ai {
                NotificationCenter.default.post(name: .resetChatToStarter, object: nil)
            }
        }
        // 灵动岛/锁屏 Live Activity 上点"打开详情"按钮跳转回 app — 由 OpenRaceDetailIntent post 通知
        .onReceive(NotificationCenter.default.publisher(for: .openRaceDetail)) { _ in
            // 跳到赛车 tab(detail navigation 由各 list view 内部 handle)
            selection = .motorsport
        }
        // 关注 tab 空状态 CTA "去赛车 tab 发现" 发出此通知 → 切到赛历 tab
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMotorsportTab)) { _ in
            selection = .motorsport
        }
        .task {
            // 首次启动若尚未询问,自动弹一次系统授权(用户可拒)。
            let status = await NotificationScheduler.shared.authorizationStatus()
            if status == .notDetermined {
                _ = await NotificationScheduler.shared.requestAuthorization()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: FollowedItem.self, inMemory: true)
}

