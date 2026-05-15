import Foundation
import os

/// 分类日志门面。Console.app + Instruments 用 subsystem `com.tiebowen.Pole` + category 过滤。
public enum PoleLog {
    public static let net      = Logger(subsystem: "com.tiebowen.Pole", category: "net")
    public static let agent    = Logger(subsystem: "com.tiebowen.Pole", category: "agent")
    public static let cache    = Logger(subsystem: "com.tiebowen.Pole", category: "cache")
    public static let liveAct  = Logger(subsystem: "com.tiebowen.Pole", category: "liveActivity")
    public static let domain   = Logger(subsystem: "com.tiebowen.Pole", category: "domain")
    public static let ui       = Logger(subsystem: "com.tiebowen.Pole", category: "ui")
}
