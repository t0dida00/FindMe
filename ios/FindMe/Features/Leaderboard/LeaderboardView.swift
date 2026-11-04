import SwiftUI

/// F-25: milestones won → total reward → total time.
struct LeaderboardView: View {
    @Environment(GameViewModel.self) private var vm

    var body: some View {
        List { ThemedRows {
            if vm.leaderboard.isEmpty {
                ContentUnavailableView("Chưa có người chơi", systemImage: "person.3")
            }
            ForEach(vm.leaderboard) { entry in
                LeaderboardRow(entry: entry, currency: vm.game?.currency ?? "VND", isMe: entry.userId == vm.myId)
            }
        } }.fmScreen()
        .refreshable { await vm.refresh() }
    }
}

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let currency: String
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.system(.title3).weight(.bold)).monospacedDigit()
                .frame(width: 36)
                .foregroundStyle(entry.rank == 1 && entry.milestonesWon > 0 ? .fmAccent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName + (isMe ? String(localized: " (bạn)") : "")).font(.headline)
                Text("\(entry.milestonesWon) mốc · \(Fmt.duration(seconds: entry.totalSeconds))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if entry.totalReward > 0 {
                Text(Fmt.money(entry.totalReward, currency: currency)).font(.fmNumber)
            }
        }
        .listRowBackground(isMe ? Color.fmAccentSoft : Color.fmSurface)
        .accessibilityElement(children: .combine)
    }
}
