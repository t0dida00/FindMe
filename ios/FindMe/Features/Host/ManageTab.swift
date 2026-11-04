import SwiftUI

/// Host/co-host control panel, top to bottom: basic info, hints (F-04..F-07), join code + start (F-09/F-10/F-11),
/// game settings (F-08), participants (F-12) and cancel.
struct ManageTab: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var showNewHint = false
    @State private var showSchedule = false
    @State private var confirmStart = false
    @State private var confirmCancel = false
    @State private var confirmDelete = false
    @State private var working = false
    @State private var error: String?
    @State private var codes: [UUID: String] = [:]

    var body: some View {
        List { ThemedRows {
            if let game = vm.game {
                infoSection(game)
                hintsSection(game)
                lobbySection(game)
                settingsSection(game)
                dangerSection(game)
            }
        } }.fmScreen()
        .refreshable { await vm.refresh(); await loadCodes() }
        .disabled(working)
        // Tải lại mã khi danh sách hint đổi (thêm hint, đặt mã mới xong quay lại).
        .task(id: vm.hostHints) { await loadCodes() }
        .sheet(isPresented: $showNewHint) { NewHintView() }
        .sheet(isPresented: $showSchedule) { ScheduleSheet() }
        .confirmationDialog("Bắt đầu game ngay?", isPresented: $confirmStart, titleVisibility: .visible) {
            Button("Bắt đầu") { act { try await API.startGame(id: vm.gameId) } }
        } message: { Text("Sau khi bắt đầu, chỉ sửa được tiêu đề, mô tả và thưởng của hint chưa giải. Vị trí, mã và khối gợi ý bị khóa.") }
        .confirmationDialog("Hủy game?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Hủy game", role: .destructive) { act { try await API.cancelGame(id: vm.gameId) } }
        } message: { Text("Mọi mã đang chờ sẽ hết hạn. Không thể hoàn tác.") }
        .confirmationDialog("Xóa bản nháp này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xóa", role: .destructive) {
                act {
                    try await API.deleteDraftGame(id: vm.gameId)
                    dismiss()
                }
            }
        }
        .errorAlert($error)
    }

    private func lobbySection(_ game: Game) -> some View {
        Section("Mã tham gia") {
            HStack {
                VStack(alignment: .leading) {
                    Text(game.joinCode).font(.system(size: 34, weight: .black).monospacedDigit()).tracking(4)
                        .textSelection(.enabled)
                }
                Spacer()
                StatusChip(text: game.status.label, color: game.status.color)
            }
            ShareLink(item: AppConfig.joinLink(code: game.joinCode),
                      message: Text("Tham gia game \"\(game.title)\" trên Find Me! Mã: \(game.joinCode)")) {
                Label("Chia sẻ mã / link mời", systemImage: "square.and.arrow.up")
            }
            if game.status == .scheduled, let at = game.startsAt {
                HStack { Text("Tự bắt đầu sau"); Spacer(); CountdownText(until: at).bold() }
            }
            if game.status.isEditable {
                Button { confirmStart = true } label: { Label("Bắt đầu ngay", systemImage: "play.fill") }
                    .disabled(vm.hostHints.isEmpty)
                Button { showSchedule = true } label: {
                    Label(game.status == .scheduled ? "Đổi giờ bắt đầu" : "Hẹn giờ bắt đầu", systemImage: "calendar.badge.clock")
                }
            }
        }
    }

    private func infoSection(_ game: Game) -> some View {
        let players = vm.participants.filter { $0.role == .player }.count
        let found = vm.hostHints.filter { $0.revealedAt != nil }.count
        return Section("Thông tin cơ bản") {
            LabeledContent("Tên game") { Text(verbatim: game.title).multilineTextAlignment(.trailing) }
            LabeledContent("Địa chỉ") {
                if let area = game.areaName, !area.isEmpty {
                    Text(verbatim: area).multilineTextAlignment(.trailing)
                } else {
                    Text("Chưa đặt")
                }
            }
            LabeledContent("Giải thưởng") {
                Text(verbatim: Fmt.prize(game.grandPrize, item: game.grandPrizeItem, currency: game.currency) ?? "—")
                    .monospacedDigit().foregroundStyle(Color.fmTreasure).bold()
                    .multilineTextAlignment(.trailing)
            }
            if let created = game.createdAt {
                LabeledContent("Ngày tạo") { Text(verbatim: Fmt.dateTime(created)).monospacedDigit() }
            }
            LabeledContent("Ngày bắt đầu") {
                if let started = game.startedAt {
                    Text(verbatim: Fmt.dateTime(started)).monospacedDigit()
                } else if let at = game.startsAt {
                    Text("Hẹn \(Fmt.dateTime(at))").monospacedDigit()
                } else {
                    Text("Chưa bắt đầu")
                }
            }
            LabeledContent("Người chơi") {
                Text(verbatim: game.maxPlayers.map { "\(players)/\($0)" } ?? "\(players)").monospacedDigit()
            }
            LabeledContent("Hint đã tìm") {
                Text(verbatim: "\(found)/\(vm.hostHints.count)").monospacedDigit()
            }
        }
    }

    @ViewBuilder private func settingsSection(_ game: Game) -> some View {
        Section("Cài đặt game") {
            NavigationLink { GameSettingsView().fmTabBarInset() } label: { Label("Cài đặt game", systemImage: "gearshape") }
            NavigationLink { ParticipantsView().fmTabBarInset() } label: {
                Label { Text("Người tham gia (\(vm.participants.count))") } icon: { Image(systemName: "person.3") }
            }
            if game.status.isFinished {
                NavigationLink { ResultsView().fmTabBarInset() } label: { Label("Kết quả", systemImage: "trophy") }
            }
        }
    }

    /// Hủy game / xóa bản nháp: section riêng, nền đỏ nhạt + chữ đỏ để không bấm nhầm.
    @ViewBuilder private func dangerSection(_ game: Game) -> some View {
        let canCancel = !game.status.isFinished
        let canDelete = game.status == .draft && vm.isHost
        if canCancel || canDelete {
            Section {
                if canCancel {
                    dangerButton("Hủy game", systemImage: "xmark.octagon.fill") { confirmCancel = true }
                }
                if canDelete {
                    dangerButton("Xóa bản nháp", systemImage: "trash.fill") { confirmDelete = true }
                }
            }
        }
    }

    private func dangerButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.fmDanger)
        }
        .listRowBackground(Color.fmDanger.opacity(0.14))
    }

    @ViewBuilder private func hintsSection(_ game: Game) -> some View {
        Section {
            if game.status == .live, let order = game.currentHintOrder {
                Label { Text("Đang mở Hint \(order) / \(vm.hostHints.count)") } icon: { Image(systemName: "dot.radiowaves.left.and.right") }
            }
            ForEach(Array(vm.hostHints.enumerated()), id: \.element.id) { index, hint in
                NavigationLink { HintEditorView(hintId: hint.id).fmTabBarInset() } label: { HostHintRow(hint: hint, game: game, code: codes[hint.id]) }
                    .swipeActions(edge: .leading) {
                        if game.status.isEditable && index > 0 {
                            Button("Lên") { act { try await API.swapHintOrder(hint, vm.hostHints[index - 1]) } }.tint(.fmInfo)
                        }
                        if game.status.isEditable && index < vm.hostHints.count - 1 {
                            Button("Xuống") { act { try await API.swapHintOrder(hint, vm.hostHints[index + 1]) } }.tint(.fmAccent)
                        }
                    }
            }
            if game.status.isEditable {
                Button { showNewHint = true } label: { Label("Thêm hint", systemImage: "plus") }
            }
        } header: {
            Text("Hint (\(vm.hostHints.count))")
        } footer: {
            if game.status.isEditable {
                Text("Vuốt sang phải để đổi thứ tự. Thêm, xóa và đổi thứ tự hint chỉ làm được trước khi bắt đầu.")
            } else if game.status == .live {
                Text("Đang diễn ra: chạm vào hint chưa giải để sửa tiêu đề, mô tả hoặc thưởng.")
            }
        }
    }

    /// Lỗi (ví dụ server chưa có bảng hint_codes) thì chỉ không hiện mã, không báo lỗi.
    private func loadCodes() async {
        if let c = try? await API.hintCodes(hintIds: vm.hostHints.map(\.id)) { codes = c }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do { try await work(); await vm.refresh() } catch { self.error = AppError.message(for: error) }
        }
    }
}

struct HostHintRow: View {
    let hint: HostHint
    let game: Game
    var code: String? = nil
    var body: some View {
        HStack {
            Text("\(hint.hintOrder)").font(.headline.monospacedDigit())
                .frame(width: 30, height: 30).background(Color.fmAccentSoft, in: Circle())
            VStack(alignment: .leading) {
                Text(hint.title ?? String(localized: "Hint \(hint.hintOrder)")).font(.fmHeadline)
                if let description = hint.description {
                    Text(description).font(.caption).foregroundStyle(Color.fmTextSecondary).lineLimit(2)
                }
                if let prize = Fmt.prize(hint.prize, item: hint.prizeItem, currency: game.currency) {
                    Label(prize, systemImage: "gift").font(.caption).foregroundStyle(.secondary)
                }
                if let code {
                    HStack(spacing: FM.xs) {
                        Image(systemName: "number").font(.caption2.weight(.bold))
                        Text(verbatim: code).font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    .foregroundStyle(Color.fmAccent)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Mã \(code)"))
                }
            }
            Spacer()
            if hint.revealedAt != nil {
                StatusChip(text: "Đã giải", color: .fmSuccess)
            } else if game.status == .live && game.currentHintOrder == hint.hintOrder {
                StatusChip(text: "Đang mở", color: .fmInfo)
            }
        }
    }
}

struct ScheduleSheet: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(3600)
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form { ThemedRows {
                DatePicker("Bắt đầu lúc", selection: $date, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                Text("Game sẽ tự bắt đầu (trễ tối đa 1 phút).").font(.footnote).foregroundStyle(.secondary)
            } }.fmScreen()
            .navigationTitle("Hẹn giờ bắt đầu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        working = true
                        Task {
                            defer { working = false }
                            do {
                                try await API.scheduleGame(id: vm.gameId, at: date)
                                vm.showBanner(String(localized: "Đã hẹn giờ bắt đầu \(Fmt.dateTime(date))"), success: true)
                                await vm.refresh()
                                dismiss()
                            } catch { self.error = AppError.message(for: error) }
                        }
                    }
                    .disabled(working)
                }
            }
            .onAppear { if let at = vm.game?.startsAt, at > Date() { date = at } }
            .errorAlert($error)
        }
    }
}

/// F-08 settings (editable while draft/scheduled).
struct GameSettingsView: View {
    @Environment(GameViewModel.self) private var vm
    @State private var form = GameForm()
    @State private var original = GameForm()
    @State private var error: String?
    @State private var saving = false
    /// Thưởng mốc bằng tiền lớn nhất (hint hiện vật không tính).
    private var maxHintPrize: Double { vm.hostHints.filter { $0.prizeItem == nil }.map(\.prize).max() ?? 0 }

    var body: some View {
        Form { ThemedRows {
            GameFormFields(form: $form,
                           currentPlayers: vm.participants.filter { $0.role == .player }.count,
                           minGrandPrize: maxHintPrize,
                           hasMoneyHintPrize: maxHintPrize > 0)
                .disabled(!(vm.game?.status.isEditable ?? false))
            if !(vm.game?.status.isEditable ?? false) {
                Text("Game đã bắt đầu nên cài đặt bị khóa.").foregroundStyle(.secondary)
            }
        } }.fmScreen()
        .navigationTitle("Cài đặt")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do {
                            try await API.updateGame(id: vm.gameId, form: form)
                            original = form
                            vm.showBanner(String(localized: "Đã lưu cài đặt"), success: true)
                            await vm.refresh()
                        } catch { self.error = AppError.message(for: error) }
                    }
                }
                .disabled(form == original || saving || (form.grandPrizeItem == nil && form.grandPrize < maxHintPrize) || !form.isPrizeValid || !form.isAreaValid || form.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let g = vm.game { form = GameForm(game: g); original = form }
        }
        .errorAlert($error)
    }
}

/// F-12: participants + co-host toggle (host only, via set_participant_role).
struct ParticipantsView: View {
    @Environment(GameViewModel.self) private var vm
    @State private var error: String?

    var body: some View {
        List(vm.participants) { p in
            HStack {
                VStack(alignment: .leading) {
                    Text(vm.name(for: p.userId)).font(.headline)
                    Text(p.role.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if vm.isHost && p.role != .host {
                    Toggle("Co-host", isOn: Binding(
                        get: { p.role == .cohost },
                        set: { on in
                            Task {
                                do {
                                    try await API.setRole(gameId: vm.gameId, userId: p.userId, role: on ? .cohost : .player)
                                    await vm.refresh()
                                } catch { self.error = AppError.message(for: error) }
                            }
                        }))
                    .fixedSize()
                }
            }
        .listRowBackground(Color.fmSurface)
        }.fmScreen()
        .navigationTitle("Người tham gia")
        .refreshable { await vm.refresh() }
        .overlay { if vm.participants.isEmpty { ContentUnavailableView("Chưa có ai", systemImage: "person.3") } }
        .errorAlert($error)
    }
}
