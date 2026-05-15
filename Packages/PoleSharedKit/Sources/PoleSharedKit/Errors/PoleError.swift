import Foundation

/// 统一应用错误类型。各 service / view 捕获后用 `PoleError.from(error)` 归一,
/// View `.failed(message:)` 直接显示 `localizedDescription` 中英文双语。
public enum PoleError: LocalizedError, Sendable {
    case network(URLError)
    case http(statusCode: Int, body: Data?)
    case decoding(String)               // 简化:存 source 描述字符串,真实 Error 写日志即可
    case rateLimited(retryAfter: TimeInterval?)
    case cancelled
    case underlying(String)             // 简化:存 localizedDescription,保留 Sendable

    public var errorDescription: String? {
        switch self {
        case .network(let urlError):
            let detail = urlError.localizedDescription
            return localized(zh: "网络不可用:\(detail)", en: "Network unavailable: \(detail)")
        case .http(let code, _):
            return localized(zh: "服务返回错误(\(code))", en: "Server error (\(code))")
        case .decoding:
            return localized(zh: "数据格式异常", en: "Data format error")
        case .rateLimited:
            return localized(zh: "请求过于频繁,稍候再试", en: "Rate limited, try again shortly")
        case .cancelled:
            return nil  // 不显示给用户
        case .underlying(let msg):
            return msg
        }
    }

    /// 把任意 `Error` 归一成 `PoleError`。`CancellationError` → `.cancelled`,
    /// `URLError` → `.network`,其他 → `.underlying(localizedDescription)`。
    public static func from(_ error: any Error) -> PoleError {
        if let e = error as? PoleError { return e }
        if error is CancellationError { return .cancelled }
        if let e = error as? URLError { return .network(e) }
        return .underlying(error.localizedDescription)
    }

    /// 内部小工具:不依赖主 app 的 L10n。读 UserDefaults["languageMode"] 决定中英。
    /// 简化版,正式 L10n 在 PoleDomain (Wave 2 后) 才有。
    private func localized(zh: String, en: String) -> String {
        let mode = UserDefaults.standard.string(forKey: "languageMode") ?? "auto"
        switch mode {
        case "zh": return zh
        case "en": return en
        default:
            // auto: 系统语言
            if Locale.current.language.languageCode?.identifier == "zh" {
                return zh
            }
            return en
        }
    }
}
