import SwiftUI
import PoleDesignSystem
import PoleDomain

/// 通用错误态组件 — 统一图标 / 标题 / 重试 CTA 风格。
/// 用法:`ErrorView(message: vm.errorMessage) { Task { await vm.load() } }`。
/// 各系列 list / detail / standings 替换 inline 错误 view 走此组件。
public struct ErrorView: View {
    let message: String
    let retry: (() -> Void)?

    public init(message: String, retry: (() -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            if let retry {
                Button {
                    retry()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(L10n.t(zh: "重试", en: "Retry"))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(DS.Palette.primary, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t(zh: "错误: \(message)", en: "Error: \(message)"))
    }
}

/// 通用空态组件 — 关注列表 / 历史 / 搜索结果 / 全赛季结束 等位置统一视觉。
/// 用法:`EmptyStateView(systemImage: "star", title: "...", subtitle: "...")`。
public struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let action: (label: String, callback: () -> Void)?

    public init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        action: (label: String, callback: () -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            if let action {
                Button {
                    action.callback()
                } label: {
                    Text(action.label)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(DS.Palette.primary, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)\(subtitle.map { ", \($0)" } ?? "")")
    }
}
