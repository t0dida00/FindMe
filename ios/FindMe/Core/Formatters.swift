import Foundation

enum Fmt {
    static func money(_ amount: Double, currency: String) -> String {
        amount.formatted(.currency(code: currency.trimmingCharacters(in: .whitespaces)).precision(.fractionLength(currency == "VND" ? 0 : 2)))
    }

    /// Giải thưởng: tên hiện vật nếu có, không thì số tiền (> 0); nil khi không có giải.
    static func prize(_ amount: Double, item: String?, currency: String) -> String? {
        if let item = item?.trimmingCharacters(in: .whitespacesAndNewlines), !item.isEmpty { return item }
        return amount > 0 ? money(amount, currency: currency) : nil
    }

    /// Số tiền rút gọn cho ô nhỏ: 1.300.000 → "1,3 tr", 2.500.000.000 → "2,5 tỷ", 850.000 → "850 N" (theo locale).
    static func compactMoney(_ amount: Double) -> String {
        amount.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func duration(seconds: Int) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropLeading
        return f.string(from: TimeInterval(max(0, seconds))) ?? "\(seconds)s"
    }

    /// Ngày giờ dạng HH:mm dd/MM/yyyy (vd. 09:00 05/11/2026), cố định cho mọi ngôn ngữ.
    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    /// Ngày dạng dd/MM/yyyy.
    static func date(_ date: Date) -> String { dateFormatter.string(from: date) }

    private static let dateTimeFormatter = fixed("HH:mm dd/MM/yyyy")
    private static let dateFormatter = fixed("dd/MM/yyyy")

    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // giữ đúng định dạng, không theo locale
        f.dateFormat = format
        return f
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }

    /// Giờ:phút theo locale (vd. dòng thời gian hint đã giải).
    static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
