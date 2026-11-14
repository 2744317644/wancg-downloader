import Foundation

enum AppDateFormatting {
    static let chineseLocale = Locale(identifier: "zh_Hans_CN")

    static func date(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .locale(chineseLocale)
        )
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(chineseLocale)
        )
    }

    static func time(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(chineseLocale)
        )
    }

    static func dateWithWeekday(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .omitted)
                .weekday(.abbreviated)
                .locale(chineseLocale)
        )
    }
}
