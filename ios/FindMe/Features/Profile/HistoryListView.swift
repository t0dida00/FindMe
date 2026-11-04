import SwiftUI

/// Một dòng lịch sử (get_my_history): vai trò · số hint đã tìm · ngày, tiền thưởng bên phải.
struct HistoryRow: View {
    let entry: HistoryEntry
    let action: () -> Void

    var body: some View {
        FMRow(systemImage: entry.role.isStaff ? "crown.fill" : "figure.walk",
              tint: entry.status == .cancelled ? .fmMuted : .fmAccent,
              title: Text(entry.title),
              subtitle: subtitle,
              action: action) {
            if entry.rewardAmount > 0 {
                Text(verbatim: Fmt.money(entry.rewardAmount, currency: entry.currency))
                    .font(.fmNumber).foregroundStyle(Color.fmTreasure)
            } else if let items = entry.rewardItems {
                Label(items, systemImage: "gift").font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.fmTreasure).lineLimit(1)
            } else if entry.status == .cancelled {
                StatusChip(text: entry.status.label, color: entry.status.color)
            }
        }
        .accessibilityHint(Text("Mở game"))
    }

    private var subtitle: Text {
        let date = Fmt.date(entry.playedAt)
        if entry.role.isStaff {
            return Text("\(Text(entry.role.label)) · \(date)")
        }
        return Text("\(Text(entry.role.label)) · \(entry.hintsFound)/\(entry.hintCount) hint · \(date)")
    }
}

/// Toàn bộ lịch sử tham gia (mở từ tab Game hoặc Hồ sơ): header riêng, chia theo
/// Tuần này / Tháng này / Cũ hơn, mỗi game là một thẻ.
struct HistoryListView: View {
    let entries: [HistoryEntry]
    let open: (UUID) -> Void

    private enum Period: CaseIterable {
        case week, month, older
        var label: LocalizedStringKey {
            switch self {
            case .week: "Tuần này"
            case .month: "Tháng này"
            case .older: "Cũ hơn"
            }
        }
    }

    var body: some View {
        FMScrollScreen {
            FMPushedHeader(title: "Lịch sử tham gia", systemImage: "clock")
            Text("\(entries.count) game bạn đã chơi hoặc tổ chức")
                .font(.subheadline).foregroundStyle(Color.fmTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FM.s)
                .padding(.top, FM.s)
            ForEach(Period.allCases, id: \.self) { period in
                let list = entries.filter { self.period(of: $0.playedAt) == period }
                if !list.isEmpty {
                    FMSectionLabel(text: period.label)
                    ForEach(list) { entry in
                        FMGroup { HistoryRow(entry: entry) { open(entry.gameId) } }
                    }
                }
            }
        }
        .fmTabBarInset()
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Lịch sử tham gia")
    }

    private func period(of date: Date) -> Period {
        let cal = Calendar.current
        if cal.isDate(date, equalTo: .now, toGranularity: .weekOfYear) { return .week }
        if cal.isDate(date, equalTo: .now, toGranularity: .month) { return .month }
        return .older
    }
}
