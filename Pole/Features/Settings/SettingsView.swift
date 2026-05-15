import SwiftUI
import UserNotifications
import PoleDesignSystem

struct SettingsView: View {
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount: Int = 0
    @AppStorage("languageMode") private var languageRaw: String = LanguageMode.zh.rawValue
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled: Bool = true
    @StateObject private var appearance = AppearanceStore.shared
    @AppStorage("leadTimeRace") private var leadTimeRace: Int = 30
    @AppStorage("leadTimeQualifying") private var leadTimeQualifying: Int = 15
    @AppStorage("greetingMode") private var greetingModeRaw: String = "racing"
    @AppStorage("reducedDecor") private var reducedDecor: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text("POLE")
                            .font(DS.Font.heroDisplay)
                            .foregroundStyle(.white)
                            .tracking(2)
                        Text(L10n.t(zh: "赛车追踪", en: "Race tracker"))
                            .font(DS.Font.numberSmall)
                            .foregroundStyle(.white.opacity(0.7))
                        CheckerStripe(.horizontal, cellSize: 4)
                            .frame(height: 6)
                            .padding(.top, DS.Spacing.xs)
                    }
                    .dsHeroBanner()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach(LanguageMode.allCases) { mode in
                        Button {
                            languageRaw = mode.rawValue
                        } label: {
                            HStack {
                                Text(mode.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if mode.rawValue == languageRaw {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .font(.subheadline.weight(.bold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.t(zh: "显示语言", en: "Display Language"))
                } footer: {
                    Text(L10n.t(zh: "切换后赛事 / 国名 / 状态等数据立即生效", en: "Switching takes effect immediately for race / country / status data"))
                        .font(.caption2)
                }

                Section {
                    SegmentedPillPicker(
                        selection: $appearance.current,
                        items: AppearanceMode.allCases
                    ) { mode in
                        Text(mode.displayLabel)
                    }
                    .padding(.vertical, DS.Spacing.xs)
                } header: {
                    Text(L10n.t(zh: "外观", en: "Appearance"))
                }

                Section(L10n.t(zh: "通知", en: "Notifications")) {
                    LabeledContent(L10n.t(zh: "系统授权", en: "System Authorization"), value: authStatusLabel)
                    if authStatus == .notDetermined {
                        Button(L10n.t(zh: "申请通知权限", en: "Request Notification Permission")) {
                            Task {
                                _ = await NotificationScheduler.shared.requestAuthorization()
                                await refresh()
                            }
                        }
                    } else if authStatus == .denied {
                        Button(L10n.t(zh: "前往系统设置开启", en: "Open System Settings")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    LabeledContent(L10n.t(zh: "已排程", en: "Scheduled"), value: "\(pendingCount)")
                    Button(L10n.t(zh: "清空全部通知", en: "Clear All Notifications"), role: .destructive) {
                        Task {
                            await NotificationScheduler.shared.cancelAll()
                            await refresh()
                        }
                    }
                }
                Section(L10n.t(zh: "灵动岛 / 锁屏陪伴", en: "Dynamic Island / Lock Screen")) {
                    Toggle(L10n.t(zh: "允许从赛事详情启动", en: "Allow start from race detail"),
                           isOn: $liveActivityEnabled)
                        .onChange(of: liveActivityEnabled) { _, newValue in
                            // 关掉时立刻停止当前所有进行中的 activity;
                            // RaceDetailView "开始跟看" 按钮自己读 @AppStorage 判断是否禁用。
                            if !newValue {
                                Task {
                                    await RaceLiveActivityCoordinator.shared.stopAll()
                                }
                            }
                        }
                }
                Section {
                    Picker(L10n.t(zh: "正赛 / Superpole Race", en: "Race / Superpole Race"),
                           selection: $leadTimeRace) {
                        ForEach(Self.leadTimeOptions, id: \.self) { m in
                            Text(leadTimeLabel(m)).tag(m)
                        }
                    }
                    Picker(L10n.t(zh: "排位 / Sprint", en: "Qualifying / Sprint"),
                           selection: $leadTimeQualifying) {
                        ForEach(Self.leadTimeOptions, id: \.self) { m in
                            Text(leadTimeLabel(m)).tag(m)
                        }
                    }
                    LabeledContent(L10n.t(zh: "练习", en: "Practice"),
                                   value: L10n.t(zh: "不推送", en: "Not pushed"))
                } header: {
                    Text(L10n.t(zh: "通知策略", en: "Notification Policy"))
                } footer: {
                    Text(L10n.t(zh: "下次拉数据时新策略生效;已排程的提醒不会自动重排",
                                en: "New policy applies at next data refresh; existing scheduled reminders unchanged"))
                        .font(.caption2)
                }
                Section(L10n.t(zh: "数据源", en: "Data Sources")) {
                    LabeledContent("F1", value: "jolpica/Ergast")
                    LabeledContent("MotoGP", value: "Pulselive")
                    LabeledContent("WorldSBK / WSSP", value: "worldsbk.com")
                    LabeledContent("Formula E", value: "Pulselive")
                }
                Section(L10n.t(zh: "AI 助手", en: "AI Assistant")) {
                    Picker(L10n.t(zh: "Greeting 风格", en: "Greeting style"),
                           selection: $greetingModeRaw) {
                        Text(L10n.t(zh: "赛车 telemetry", en: "Racing telemetry")).tag("racing")
                        Text(L10n.t(zh: "友好对话", en: "Friendly")).tag("friendly")
                    }
                }
                Section(L10n.t(zh: "视觉装饰", en: "Visual Decoration")) {
                    Toggle(L10n.t(zh: "减少装饰", en: "Reduce decoration"),
                           isOn: $reducedDecor)
                }
                Section(L10n.t(zh: "关于", en: "About")) {
                    LabeledContent(L10n.t(zh: "版本", en: "Version")) {
                        Text(appVersion)
                            .font(DS.Font.numberSmall)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t(zh: "设置", en: "Settings"))
            .task { await refresh() }
        }
    }

    /// lead time picker 选项 — 5 / 15 / 30 / 45 / 60 分钟,覆盖大多数偏好。
    private static let leadTimeOptions: [Int] = [5, 15, 30, 45, 60]

    private func leadTimeLabel(_ minutes: Int) -> String {
        L10n.t(zh: "提前 \(minutes) 分钟", en: "\(minutes) min before")
    }

    private func refresh() async {
        authStatus = await NotificationScheduler.shared.authorizationStatus()
        pendingCount = await NotificationScheduler.shared.pendingCount()
    }

    private var authStatusLabel: String {
        switch authStatus {
        case .authorized:    return L10n.t(zh: "已开启", en: "Enabled")
        case .denied:        return L10n.t(zh: "已拒绝", en: "Denied")
        case .notDetermined: return L10n.t(zh: "未询问", en: "Not Asked")
        case .provisional:   return L10n.t(zh: "临时授权", en: "Provisional")
        case .ephemeral:     return L10n.t(zh: "临时", en: "Ephemeral")
        @unknown default:    return L10n.t(zh: "未知", en: "Unknown")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
}
