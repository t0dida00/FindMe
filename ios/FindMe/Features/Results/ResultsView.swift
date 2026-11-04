import MapKit
import SwiftUI

/// F-28: grand winner, leaderboard, journey map, share button.
struct ResultsView: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.displayScale) private var displayScale
    @State private var shareImage: Image?

    var body: some View {
        FMScrollScreen {
            ResultsCard(game: vm.game, grandWinner: grandWinnerName, top: Array(vm.leaderboard.prefix(5)),
                        hintsSolved: vm.revealedAnswers.count)
            if let game = vm.game, game.status.isFinished, !vm.isStaff {
                HostRatingCard(gameId: game.id, hostName: vm.name(for: game.hostId))
            }
            if !vm.revealedAnswers.isEmpty {
                VStack(alignment: .leading) {
                    Text("Hành trình").font(.fmTitle3)
                    JourneyMiniMap(answers: vm.revealedAnswers)
                }
            }
            VStack(alignment: .leading) {
                Text("Bảng xếp hạng").font(.fmTitle3)
                ForEach(vm.leaderboard) { e in
                    LeaderboardRow(entry: e, currency: vm.game?.currency ?? "VND", isMe: e.userId == vm.myId)
                    Divider()
                }
            }
            if let shareImage, let game = vm.game {
                ShareLink(item: shareImage,
                          subject: Text("Find Me!"),
                          message: Text("Kết quả game \"\(game.title)\" trên Find Me!"),
                          preview: SharePreview(Text(game.title), image: shareImage)) {
                    Label("Chia sẻ kết quả", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.fmPrimary)
            }
        }
        .refreshable { await vm.refresh() }
        .task(id: vm.leaderboard) { renderShareImage() }
    }

    private var grandWinnerName: String? {
        guard let grand = vm.rewards.first(where: { $0.kind == .grand }) else { return nil }
        return vm.name(for: grand.winnerId)
    }

    private func renderShareImage() {
        let card = ResultsCard(game: vm.game, grandWinner: grandWinnerName, top: Array(vm.leaderboard.prefix(5)),
                               hintsSolved: vm.revealedAnswers.count)
            .frame(width: 360).padding().background(Color.fmCanvas)
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
    }
}

struct ResultsCard: View {
    let game: Game?
    let grandWinner: String?
    let top: [LeaderboardEntry]
    let hintsSolved: Int

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: game?.status == .cancelled ? "xmark.octagon" : "trophy.fill")
                .font(.system(size: 52)).foregroundStyle(.fmAccent)
            Text(game?.title ?? "").font(.fmTitle).multilineTextAlignment(.center)
            if game?.status == .cancelled {
                Text("Game đã bị hủy").foregroundStyle(.fmDanger)
            } else if let grandWinner {
                Text("Người thắng giải tổng").font(.caption).foregroundStyle(.secondary)
                Text(grandWinner).font(.system(.title).weight(.bold))
                if let game, let prize = Fmt.prize(game.grandPrize, item: game.grandPrizeItem, currency: game.currency) {
                    Text(verbatim: prize).multilineTextAlignment(.center)
                        .font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Color.fmTreasure)
                }
            }
            Text("\(hintsSolved) hint đã được giải").font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 4) {
                ForEach(top) { e in
                    HStack {
                        Text("#\(e.rank)").bold().monospacedDigit()
                        Text(e.displayName)
                        Spacer()
                        Text("\(e.milestonesWon) mốc").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
            Text("Find Me!").font(.caption.weight(.heavy)).foregroundStyle(.fmAccent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.fmBorder))
    }
}

struct JourneyMiniMap: View {
    let answers: [RevealedAnswer]
    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.zoom, .pan]) {
            if answers.count > 1 {
                MapPolyline(coordinates: answers.map(\.coordinate)).stroke(.fmAccent, lineWidth: 4)
            }
            ForEach(answers) { a in
                Marker(a.winnerName, monogram: Text("\(a.hintOrder)"), coordinate: a.coordinate).tint(.fmAccent)
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
