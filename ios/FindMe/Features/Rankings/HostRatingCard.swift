import SwiftUI

/// Người chơi chấm 1–5 sao cho quản trò sau khi game kết thúc (rate_host).
/// Điểm này là "độ uy tín" trên bảng xếp hạng Quản trò. Chấm lại sẽ ghi đè.
struct HostRatingCard: View {
    let gameId: UUID
    let hostName: String
    @State private var stars: Int?
    @State private var saving = false
    @State private var justSaved = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 10) {
            Text("Chấm điểm quản trò").font(.fmTitle3)
            Text("Game do \(hostName) tổ chức thế nào?")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    Button { Task { await rate(n) } } label: {
                        Image(systemName: n <= (stars ?? 0) ? "star.fill" : "star")
                            .font(.title)
                            .foregroundStyle(n <= (stars ?? 0) ? Color.fmAccent : Color.fmMuted)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(saving)
                    .accessibilityLabel(Text("\(n) sao"))
                    .accessibilityAddTraits(n == stars ? .isSelected : [])
                }
            }
            Text(justSaved ? "Cảm ơn bạn đã đánh giá!" : (stars == nil ? "Chạm vào sao để chấm" : "Chạm để đổi đánh giá"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .fmCard()
        .sensoryFeedback(.selection, trigger: stars)
        .task { stars = try? await API.myHostRating(gameId: gameId) }
        .errorAlert($error)
    }

    private func rate(_ n: Int) async {
        let previous = stars
        stars = n
        saving = true
        defer { saving = false }
        do {
            try await API.rateHost(gameId: gameId, stars: n)
            justSaved = true
        } catch {
            stars = previous
            self.error = AppError.message(for: error)
        }
    }
}
