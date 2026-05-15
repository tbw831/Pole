import SwiftUI
#if canImport(UIKit) && canImport(SafariServices)
import UIKit
import SafariServices
#endif

#if canImport(UIKit) && canImport(SafariServices)
/// SwiftUI wrapper for SFSafariViewController——在 app 内 modal 打开 URL,
/// 比跳出系统浏览器更顺滑。WSSP PDF results 用它显示。
public struct SafariView: UIViewControllerRepresentable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

/// .sheet(item:) 需要 Identifiable;裸 URL 不行。
public struct IdentifiableURL: Identifiable {
    public let id = UUID()
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}
