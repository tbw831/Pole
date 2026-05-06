import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

private let snapshotLog = Logger(subsystem: "com.tiebowen.Pole", category: "WidgetSnapshot")

/// 读 / 写 widget_snapshot.json。
/// - 主 app 调 `write(_:)`,会同时触发 WidgetCenter reload。
/// - Widget extension 调 `read()` 拿当前 snapshot。
public enum WidgetSnapshotStore {
    /// 读取 snapshot。container 不存在 / 文件不存在 / 解码失败均返 nil。
    /// 解码失败 / 写入失败现在通过 `os.Logger` 落日志(老逻辑 `try?` 静默吞,
    /// widget 显示"赛季结束"占位但无信号,主 app 加新字段时旧 widget 二进制读不到也无定位)。
    public static func read() -> WidgetSnapshot? {
        guard let url = AppGroup.snapshotURL else {
            snapshotLog.error("read: AppGroup.snapshotURL nil — App Group capability 没配?")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // 文件不存在是正常的(主 app 还没启动一次写过)
            if (error as NSError).code != NSFileReadNoSuchFileError {
                snapshotLog.warning("read: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(WidgetSnapshot.self, from: data)
        } catch {
            snapshotLog.error("decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 写入 snapshot。失败时落日志(widget 会显示上次的或占位)。
    /// 写入后调 WidgetCenter 让所有 widget 重新拉 timeline。
    public static func write(_ snapshot: WidgetSnapshot) {
        guard let url = AppGroup.snapshotURL else {
            snapshotLog.error("write: AppGroup.snapshotURL nil")
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            snapshotLog.error("encode failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            snapshotLog.error("write to disk failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
