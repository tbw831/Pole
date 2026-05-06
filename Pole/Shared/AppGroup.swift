import Foundation

/// 主 app 与 widget extension 共享数据的 App Group。
/// 标识符必须和两个 target 的 .entitlements 完全一致。
public enum AppGroup {
    public static let identifier = "group.com.tiebowen.Pole"

    /// 共享 container 根目录。entitlement 缺失或拼写错时返 nil。
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// widget snapshot JSON 路径。
    public static var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget_snapshot.json")
    }
}
