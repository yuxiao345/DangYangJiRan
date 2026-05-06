import Foundation

enum DateFormatters {
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日"
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f
    }()

    static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
}
