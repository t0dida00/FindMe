import PhotosUI
import SwiftUI

/// F-02 (display name + avatar) + N-11 delete account.
/// Bố cục: thẻ hồ sơ (avatar · tên · Sửa), lưới thống kê (get_my_stats), lịch sử tham gia
/// (get_my_history), rồi các nhóm cài đặt và tài khoản.
struct ProfileView: View {
    /// Mở một game từ lịch sử (MainTabView trình bày GameScreen).
    let open: (UUID) -> Void
    /// Tăng lên mỗi khi GameScreen đóng, để tải lại thống kê và lịch sử.
    let reloadTick: Int
    @Environment(AuthStore.self) private var auth
    @State private var profile: Profile?
    @State private var stats: MyStats?
    @State private var history: [HistoryEntry] = []
    @State private var name = ""
    @State private var saving = false
    @State private var editingName = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploadingAvatar = false

    private static let maxNameLength = 40
    private static let recentCount = 3
    private var email: String? { Supa.client.auth.currentUser?.email }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && trimmedName != profile?.displayName && !saving }

    var body: some View {
        NavigationStack {
            FMScrollScreen {
                header.padding(.top, FM.s)
                statsGrid
                historySection
                settingsSection
                accountSection
                versionFooter
            }
            .fmTabBarInset()
            .refreshable { await load() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("ME")
            .task { await load() }
            .onChange(of: reloadTick) { _, _ in Task { await load() } }
            .onChange(of: name) { _, n in
                if n.count > Self.maxNameLength { name = String(n.prefix(Self.maxNameLength)) }
            }
            .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in if let item { Task { await uploadAvatar(item) } } }
            .sheet(isPresented: $editingName) { nameSheet }
            .confirmationDialog("Xóa tài khoản vĩnh viễn?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Xóa tài khoản", role: .destructive) { Task { await deleteAccount() } }
            } message: {
                Text("Hành động này không thể hoàn tác.")
            }
            .errorAlert($error)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: FM.pad) {
            Menu {
                Button { showPicker = true } label: {
                    Label(profile?.avatarPath == nil ? "Chọn ảnh đại diện" : "Đổi ảnh đại diện",
                          systemImage: "photo.on.rectangle")
                }
                if profile?.avatarPath != nil {
                    Button(role: .destructive) { Task { await removeAvatar() } } label: {
                        Label("Xóa ảnh đại diện", systemImage: "trash")
                    }
                }
            } label: {
                avatar
            }
            .disabled(profile == nil || uploadingAvatar)
            .accessibilityLabel(Text("Ảnh đại diện"))
            .accessibilityHint(Text("Chạm để đổi ảnh đại diện"))

            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayName ?? " ")
                    .font(.fmTitle).foregroundStyle(Color.fmText)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .redacted(reason: profile == nil ? .placeholder : [])
                if let email {
                    Text(email).font(.footnote).foregroundStyle(Color.fmTextSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button { name = profile?.displayName ?? ""; editingName = true } label: {
                Label("Sửa", systemImage: "pencil")
            }
            .buttonStyle(.fmPill)
            .disabled(profile == nil)
        }
        .padding(FM.pad)
        .background(Color.fmSurface, in: RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
    }

    private var avatar: some View {
        AvatarView(path: profile?.avatarPath, name: profile?.displayName ?? name, size: 64)
            .overlay {
                if uploadingAvatar {
                    Circle().fill(.black.opacity(0.35))
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 80, height: 80)
            .background(Color.fmAccentSoft, in: RoundedRectangle(cornerRadius: FM.radiusLarge - 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge - 4, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fmOnAccent)
                    .frame(width: 26, height: 26)
                    .background(Color.fmAccent, in: Circle())
                    .overlay(Circle().strokeBorder(Color.fmSurface, lineWidth: 2))
                    .offset(x: 6, y: 6)
            }
            .contentShape(Rectangle())
    }

    private var nameSheet: some View {
        NavigationStack {
            Form { ThemedRows {
                Section {
                    HStack {
                        TextField("Tên của bạn", text: $name)
                            .textContentType(.name)
                            .submitLabel(.done)
                            .onSubmit { if canSave { Task { await save() } } }
                        Text(verbatim: "\(name.count)/\(Self.maxNameLength)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.fmTextSecondary)
                    }
                } header: {
                    Text("Tên hiển thị")
                } footer: {
                    Text("Tên này hiển thị với quản trò và người chơi khác.")
                }
            } }
            .fmScreen()
            .navigationTitle("Sửa hồ sơ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { editingName = false } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Lưu") { Task { await save() } }.disabled(!canSave)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Thống kê

    private var statsGrid: some View {
        FMTileGrid() {
            StatCard(systemImage: "figure.walk", tint: .fmAccent, label: "Game đã chơi",
                     value: Text(verbatim: (stats?.gamesPlayed ?? 0).formatted()))
            StatCard(systemImage: "mappin.and.ellipse", tint: .fmSuccess, label: "Hint đã tìm",
                     value: Text(verbatim: (stats?.hintsFound ?? 0).formatted()))
            StatCard(systemImage: "gift.fill", tint: .fmTreasure, label: "Giải thưởng",
                     value: prizeText, valueColor: .fmTreasure,
                     detail: (stats?.gamesWon ?? 0) > 0 ? Text("Thắng chung cuộc \(stats?.gamesWon ?? 0) lần") : nil)
            StatCard(systemImage: "crown.fill", tint: .fmInfo, label: "Đã tổ chức",
                     value: Text(verbatim: (stats?.gamesHosted ?? 0).formatted()))
        }
    }

    /// Tổng tiền thưởng (nhiều loại tiền nối bằng dấu chấm giữa), thêm số hiện vật đã nhận.
    private var prizeText: Text {
        let prizes = stats?.prizes ?? []
        let items = stats?.itemsWon ?? 0
        let money = prizes.map { Fmt.money($0.amount, currency: $0.currency) }.joined(separator: " · ")
        switch (money.isEmpty, items > 0) {
        case (true, false): return Text(verbatim: Fmt.money(0, currency: "VND"))
        case (true, true): return Text("\(items) hiện vật")
        case (false, false): return Text(verbatim: money)
        case (false, true): return Text("\(money) · \(items) hiện vật")
        }
    }

    // MARK: Lịch sử

    @ViewBuilder private var historySection: some View {
        FMSectionLabel(text: "Lịch sử tham gia")
        if history.isEmpty {
            FMGroup {
                FMRow(systemImage: "clock", title: Text("Chưa có game nào"),
                      subtitle: Text("Các game bạn chơi hoặc tổ chức sẽ hiện ở đây."))
            }
        } else {
            FMGroup {
                ForEach(Array(history.prefix(Self.recentCount).enumerated()), id: \.element.id) { i, entry in
                    if i > 0 { FMGroupDivider() }
                    HistoryRow(entry: entry) { open(entry.gameId) }
                }
                if !history.isEmpty {
                    FMGroupDivider()
                    NavigationLink {
                        HistoryListView(entries: history, open: open)
                    } label: {
                        FMRow(systemImage: "clock.arrow.circlepath", title: Text("Tất cả \(history.count) game"),
                              chevron: false) {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold)).foregroundStyle(Color.fmTextSecondary)
                        }
                    }
                    .buttonStyle(FMRowPressStyle())
                }
            }
        }
    }

    // MARK: Cài đặt + tài khoản

    @ViewBuilder private var settingsSection: some View {
        FMSectionLabel(text: "Cài đặt")
        FMGroup {
            FMRow(systemImage: "globe", tint: .pink, title: Text("Ngôn ngữ"), action: openSettings) {
                Text(verbatim: Bundle.main.preferredLocalizations.first == "en" ? "English" : "Tiếng Việt")
                    .foregroundStyle(Color.fmTextSecondary)
            }
        }
    }

    @ViewBuilder private var accountSection: some View {
        FMSectionLabel(text: "Tài khoản")
        FMGroup {
            FMRow(systemImage: "rectangle.portrait.and.arrow.right", title: Text("Đăng xuất"), chevron: false) {
                Task { await auth.signOut() }
            }
            FMGroupDivider()
            FMRow(systemImage: "trash", tint: .fmDanger, title: Text("Xóa tài khoản"),
                  subtitle: Text("Xóa vĩnh viễn hồ sơ, các game bạn tạo và mã của bạn."),
                  titleColor: .fmDanger, chevron: false) {
                confirmDelete = true
            }
        }
    }

    private var versionFooter: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return Text("Phiên bản \(version) (\(build))")
            .font(.footnote).foregroundStyle(Color.fmTextSecondary)
            .padding(.top, FM.pad)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: Actions

    private func load() async {
        async let me = API.myProfile()
        async let st = API.myStats()
        async let hist = API.myHistory()
        do {
            let p = try await me
            profile = p
            if !editingName { name = p.displayName }
        } catch { self.error = AppError.message(for: error) }
        // Không nuốt lỗi: thiếu hàm ở server thì phải báo, không thì mọi ô thống kê cứ hiện 0.
        do { stats = try await st } catch { if self.error == nil { self.error = AppError.message(for: error) } }
        do { history = try await hist } catch { if self.error == nil { self.error = AppError.message(for: error) } }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let trimmed = trimmedName
        do {
            try await API.updateDisplayName(trimmed)
            profile?.displayName = trimmed
            name = trimmed
            editingName = false
        } catch { self.error = AppError.message(for: error) }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        uploadingAvatar = true
        defer { uploadingAvatar = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                  let jpeg = ImageCompressor.squareAvatar(from: image)
            else { throw API.APIError.compressionFailed }
            let path = try await API.updateAvatar(jpeg: jpeg)
            withAnimation { profile?.avatarPath = path }
        } catch { self.error = AppError.message(for: error) }
    }

    private func removeAvatar() async {
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        do {
            try await API.removeAvatar()
            withAnimation { profile?.avatarPath = nil }
        } catch { self.error = AppError.message(for: error) }
    }

    private func deleteAccount() async {
        do {
            try await API.deleteMyAccount()
            await auth.signOut()
        } catch { self.error = AppError.message(for: error) }
    }
}

/// Ô thống kê trong lưới 2 cột: ô icon, con số lớn, nhãn (và dòng phụ nếu có).
private struct StatCard: View {
    let systemImage: String
    let tint: Color
    let label: LocalizedStringKey
    let value: Text
    var valueColor: Color = .fmText
    var detail: Text?

    var body: some View {
        VStack(alignment: .leading, spacing: FM.s) {
            FMIconTile(systemImage: systemImage, tint: tint, size: 36)
            value
                .font(.system(.title2).weight(.bold)).monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Color.fmTextSecondary)
            if let detail {
                detail.font(.caption).foregroundStyle(Color.fmTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(FM.pad)
        .background {
            RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                .fill(Color.fmSurface)
                .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.12), .clear], startPoint: .top, endPoint: .bottom)))
        }
        .overlay(RoundedRectangle(cornerRadius: FM.radiusLarge, style: .continuous).strokeBorder(Color.fmBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
