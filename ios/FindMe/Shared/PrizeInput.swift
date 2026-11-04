import SwiftUI

/// Quy tắc nhập giải thưởng (khớp 20261103001800_item_prizes.sql): mỗi giải là tiền hoặc hiện vật.
enum PrizeInput {
    /// Tên hiện vật tối đa 120 ký tự (check constraint ở server).
    static let maxItemLength = 120

    static func isValidItem(_ name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= maxItemLength
    }

    /// Thưởng mốc bằng tiền vượt giải tổng bằng tiền? (hiện vật thì không so được)
    static func exceedsCap(amount: Double, item: String?, cap: Double?) -> Bool {
        guard item == nil, let cap else { return false }
        return amount > cap
    }
}

/// Các dòng nhập một giải trong Form: chọn Tiền / Hiện vật, rồi số tiền hoặc tên món quà.
/// `item == nil` nghĩa là tiền; chọn "Hiện vật" đặt `item = ""` để người dùng gõ tên.
struct PrizeFields: View {
    let label: LocalizedStringKey
    @Binding var amount: Double
    @Binding var item: String?
    let currency: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Picker(label, selection: isItem) {
                Text("Tiền").tag(false)
                Text("Hiện vật").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()
        }
        if item == nil {
            HStack {
                Text("Số tiền")
                Spacer()
                TextField("0", value: $amount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text(currency).foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Image(systemName: "gift").foregroundStyle(Color.fmAccent).accessibilityHidden(true)
                TextField("Tên món quà, vd. Tai nghe AirPods", text: itemText)
            }
        }
    }

    private var isItem: Binding<Bool> {
        Binding(get: { item != nil },
                set: { item = $0 ? (item ?? "") : nil })
    }

    private var itemText: Binding<String> {
        Binding(get: { item ?? "" },
                set: { item = String($0.prefix(PrizeInput.maxItemLength)) })
    }
}
