import SwiftUI
import SafariServices

/// SwiftUI wrapper for SFSafariViewController——在 app 内 modal 打开 URL,
/// 比跳出系统浏览器更顺滑。WSSP PDF results 用它显示。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// .sheet(item:) 需要 Identifiable;裸 URL 不行。
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
