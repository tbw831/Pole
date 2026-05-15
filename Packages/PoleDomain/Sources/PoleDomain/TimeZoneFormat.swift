import Foundation

public extension TimeZone {
    /// 北京时间(Asia/Shanghai,UTC+8)。app 仅自用,所有时间都按这个时区显示。
    static let beijing = TimeZone(identifier: "Asia/Shanghai")!
}

public extension Date.FormatStyle {
    /// 把任意 dateTime FormatStyle 强制成北京时区,例如:
    /// `Text(race.startTime, format: .dateTime.year().month().day().hour().minute().beijing())`
    /// 注意:`Date.FormatStyle.timeZone(_:)` 是配置 timezone display symbol 的方法,
    /// 设置实际换算时区要直接给 stored property 赋值。
    func beijing() -> Date.FormatStyle {
        var copy = self
        copy.timeZone = .beijing
        return copy
    }
}
