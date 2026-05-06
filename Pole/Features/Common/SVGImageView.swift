import SwiftUI
import WebKit

/// SwiftUI wrapper 用 WKWebView 渲染 SVG——AsyncImage / UIImage 都不支持 SVG,
/// WKWebView 是 iOS 上最简单(无第三方依赖)的方案。
///
/// **直接 load(URLRequest) 会让 SVG 显示在 WebView 左上角**(默认无 CSS 居中)。
/// 这里用 HTML wrapper 包一层 flex 容器 + `object-fit: contain` 让 SVG 在容器内
/// **等比缩放居中**,适配任何 banner 尺寸。
struct SVGImageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.bouncesZoom = false
        view.scrollView.contentInset = .zero
        load(into: view)
        // 标记当前 url 用于 update 时跳过重复加载
        context.coordinator.currentURL = url
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.currentURL != url {
            load(into: uiView)
            context.coordinator.currentURL = url
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var currentURL: URL?
    }

    /// 远程 URL 直接 img src 全 URL;file:// URL 用 baseURL=父目录 + img src=文件名,
    /// 否则 WKWebView sandbox 会 block file:// 资源。
    private func load(into webView: WKWebView) {
        let imgSrc: String
        let baseURL: URL?
        if url.isFileURL {
            imgSrc = url.lastPathComponent
            baseURL = url.deletingLastPathComponent()
        } else {
            imgSrc = url.absoluteString
            baseURL = nil
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
            <style>
                html, body {
                    margin: 0;
                    padding: 0;
                    width: 100%;
                    height: 100%;
                    background: transparent;
                    overflow: hidden;
                }
                body {
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                img {
                    max-width: 100%;
                    max-height: 100%;
                    width: auto;
                    height: auto;
                    object-fit: contain;
                }
            </style>
        </head>
        <body>
            <img src="\(imgSrc)" />
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}
