import PhotosUI
import MapKit
import SwiftUI

/// F-03 create game, as a 3-step wizard: 1. thông tin chung → 2. hint → 3. xem lại → Tạo.
/// A hunt needs at least one hint: "Tiếp" on step 2 and "Tạo" stay disabled until there is one
/// (the server also refuses to schedule a hunt without hints or to delete its last hint).
/// Nothing reaches the server until "Tạo": then the game and its hints are created in order.
/// Leaving midway asks first: keep the draft on this device (resumed next time) or discard everything.
/// If any hint fails, the new draft is deleted again so no half-made hunt is left behind.
/// Codes are stored only as hashes, so the proof sheets are shown once right after creating.
struct CreateGameView: View {
    enum Step: Int, CaseIterable {
        case info, hints, review
        var title: LocalizedStringKey {
            switch self {
            case .info: "Thông tin"
            case .hints: "Hint"
            case .review: "Xem lại"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    let onCreated: (Game) -> Void
    @State private var step: Step = .info
    @State private var form = GameForm()
    @State private var hints: [DraftHint] = []
    @State private var editing: DraftHint?
    @State private var working = false
    @State private var error: String?
    @State private var created: Game?
    @State private var proofPages: [ProofPage] = []
    @State private var showProofs = false
    @State private var confirmExit = false
    @State private var resumed = false
    /// nil = để bản nháp, tự bấm Bắt đầu sau; khác nil = hẹn giờ ngay khi tạo.
    @State private var startsAt: Date?

    private var hasContent: Bool { form != GameForm() || !hints.isEmpty || startsAt != nil }
    private var startsAtValid: Bool { startsAt.map { $0 > Date() } ?? true }

    private var infoValid: Bool {
        !form.title.trimmingCharacters(in: .whitespaces).isEmpty && form.isAreaValid && form.isPrizeValid && startsAtValid
    }

    private var hintsValid: Bool {
        hints.contains { $0.pin != nil } && !hints.contains(where: overCap)
    }

    private func overCap(_ h: DraftHint) -> Bool {
        PrizeInput.exceedsCap(amount: h.prize, item: h.prizeItem, cap: form.grandPrizeCap)
    }

    var body: some View {
        NavigationStack {
            Form { ThemedRows {
                Section { StepIndicator(current: step) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if resumed {
                    Section {
                        Label("Bạn đang soạn tiếp bản nháp đã giữ.", systemImage: "tray.and.arrow.down")
                            .font(.subheadline)
                        Button("Bỏ nháp, làm lại từ đầu", role: .destructive) { startOver() }
                    }
                }
                switch step {
                case .info: GameFormFields(form: $form, startsAt: $startsAt,
                                           hasMoneyHintPrize: hints.contains { $0.prizeItem == nil && $0.prize > 0 })
                case .hints: hintsStep
                case .review: reviewStep
                }
            } }.fmScreen()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Tạo game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { exit() } }
            }
            .disabled(working)
            .overlay { if working { FMLoadingOverlay(message: "Đang tạo game…") } }
            .interactiveDismissDisabled(hasContent)
            .confirmationDialog("Thoát tạo game?", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("Giữ nháp") { WizardDraftStore.save(.init(form: form, hints: hints, step: step.rawValue, startsAt: startsAt)); dismiss() }
                Button("Xóa nháp", role: .destructive) { WizardDraftStore.clear(); dismiss() }
                Button("Tiếp tục soạn", role: .cancel) {}
            } message: {
                Text("Game chưa được tạo. Nếu không giữ nháp, mọi thông tin và hint bạn đã nhập sẽ bị xóa.")
            }
            .onAppear(perform: restore)
            .sheet(item: $editing) { draft in
                DraftHintEditor(draft: draft, order: order(of: draft), currency: form.currency, grandPrizeCap: form.grandPrizeCap) { saved in
                    if let i = hints.firstIndex(where: { $0.id == saved.id }) { hints[i] = saved }
                    else { hints.append(saved) }
                }
            }
            .sheet(isPresented: $showProofs, onDismiss: finish) {
                ProofSheetView(pages: proofPages, gameTitle: created?.title ?? form.title)
            }
            .errorAlert($error)
        }
    }

    // MARK: Step 2

    @ViewBuilder private var hintsStep: some View {
        Section {
            ForEach(hints) { h in
                Button { editing = h } label: { DraftHintRow(hint: h, order: order(of: h), currency: form.currency) }
                    .buttonStyle(.plain)
            }
            .onDelete { hints.remove(atOffsets: $0) }
            .onMove { hints.move(fromOffsets: $0, toOffset: $1) }
            Button {
                editing = DraftHint()
            } label: {
                Label("Thêm hint", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Hint (\(hints.count))")
        } footer: {
            VStack(alignment: .leading, spacing: FM.s) {
                if hints.isEmpty {
                    Label("Cần ít nhất một hint để tạo game.", systemImage: "info.circle")
                        .foregroundStyle(Color.fmAccent)
                }
                if hints.contains(where: overCap) {
                    Label("Thưởng mốc không được lớn hơn giải thưởng tổng (\(Fmt.money(form.grandPrize, currency: form.currency))).", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.fmDanger)
                }
                Text("Người chơi giải lần lượt theo thứ tự này. Chạm để sửa, vuốt để xóa, giữ và kéo để đổi thứ tự. Khối gợi ý (chữ, ảnh, bản đồ) thêm sau ở tab Quản lý.")
            }
        }
    }

    // MARK: Step 3

    @ViewBuilder private var reviewStep: some View {
        Section("Thông tin") {
            LabeledContent("Tiêu đề", value: form.title.trimmingCharacters(in: .whitespaces))
            if let d = form.description.trimmedOrNil {
                Text(d).font(.subheadline).foregroundStyle(Color.fmTextSecondary)
            }
            LabeledContent("Giải thưởng tổng",
                           value: Fmt.prize(form.grandPrize, item: form.grandPrizeItem, currency: form.currency) ?? "—")
            LabeledContent("Chế độ") {
                Text(form.isPublic ? "Công khai" : "Riêng tư")
            }
            if let area = form.areaName?.trimmedOrNil {
                LabeledContent("Địa chỉ", value: area)
            }
            LabeledContent("Thời gian") {
                Text(verbatim: startsAt.map(Fmt.dateTime) ?? String(localized: "Tự bấm bắt đầu"))
            }
            LabeledContent("Người chơi") { Text("Tối đa \(form.maxPlayers) người chơi") }
        }
        if hints.contains(where: { $0.pin != nil }) || form.areaLat != nil {
            Section {
                ReviewMap(hints: hints, area: areaCoordinate) { editing = $0 }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Bản đồ")
            } footer: {
                Text(form.areaLat != nil ? "Kiểm tra lại ghim đáp án của từng hint và khu vực game (vòng tròn). Chạm vào ghim để sửa hint."
                                         : "Kiểm tra lại ghim đáp án của từng hint. Chạm vào ghim để sửa hint.")
            }
        }
        Section {
            if hints.isEmpty {
                Text("Chưa có hint nào. Cần ít nhất một hint để tạo game.")
                    .font(.subheadline).foregroundStyle(Color.fmDanger)
            }
            ForEach(hints) { h in DraftHintRow(hint: h, order: order(of: h), currency: form.currency) }
        } header: {
            Text("Hint (\(hints.count))")
        } footer: {
            if !hints.isEmpty {
                Text("Sau khi tạo, app hiện tờ mã của mọi hint để bạn in hoặc lưu PDF. Mã chỉ hiển thị một lần.")
            }
        }
        Section {
            Button { step = .info } label: { Label("Sửa thông tin", systemImage: "pencil") }
            Button { step = .hints } label: { Label("Sửa hint", systemImage: "list.number") }
        }
    }

    private var areaCoordinate: CLLocationCoordinate2D? {
        guard let lat = form.areaLat, let lng = form.areaLng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .info {
                Button { go(-1) } label: {
                    Text("Quay lại").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.fmSecondary)
            }
            if step == .review {
                Button { Task { await create() } } label: {
                    Text("Tạo game").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.fmPrimary)
                .disabled(!infoValid || !hintsValid || working)
            } else {
                Button { go(1) } label: {
                    Text("Tiếp").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.fmPrimary)
                .disabled((step == .info && !infoValid) || (step == .hints && !hintsValid))
            }
        }
        .padding(.horizontal).padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Draft

    private func exit() {
        if hasContent { confirmExit = true } else { WizardDraftStore.clear(); dismiss() }
    }

    private func restore() {
        guard !resumed, !hasContent, let d = WizardDraftStore.load() else { return }
        form = d.form
        hints = d.hints
        startsAt = d.startsAt.flatMap { $0 > Date() ? $0 : nil }
        step = Step(rawValue: d.step) ?? .info
        resumed = true
    }

    private func startOver() {
        WizardDraftStore.clear()
        withAnimation {
            form = GameForm()
            hints = []
            startsAt = nil
            step = .info
            resumed = false
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation { step = next }
    }

    private func order(of h: DraftHint) -> Int {
        (hints.firstIndex { $0.id == h.id } ?? hints.count) + 1
    }

    // MARK: Create

    private func create() async {
        guard hintsValid else { return }
        working = true
        defer { working = false }
        var f = form
        f.title = f.title.trimmingCharacters(in: .whitespaces)
        let game: Game
        do {
            game = try await API.createGame(f)
        } catch {
            self.error = AppError.message(for: error)
            return
        }
        do {
            var pages: [ProofPage] = []
            for (i, h) in hints.enumerated() {
                guard let pin = h.pin else { continue }
                let hintId = try await API.createHint(gameId: game.id, order: i + 1, code: h.code,
                                                      lat: pin.latitude, lng: pin.longitude, prize: h.prize,
                                                      prizeItem: h.prizeItem,
                                                      title: h.title.trimmedOrNil, description: h.details.trimmedOrNil)
                if let data = h.imageFile.flatMap(DraftHintImages.load) {
                    let path = try await API.uploadHintImage(gameId: game.id, data: data)
                    try await API.insertHintItem(HintItemDraft(hintId: hintId, itemOrder: 1, type: .image,
                                                               textContent: nil, imagePath: path,
                                                               mapRadiusM: nil, revealAfterMinutes: nil))
                }
                pages.append(ProofPage(code: h.code, hintOrder: i + 1, hintTitle: h.title.trimmedOrNil))
            }
            if let at = startsAt { try await API.scheduleGame(id: game.id, at: at) }
            WizardDraftStore.clear()
            PushManager.shared.requestAuthorizationIfNeeded()
            created = game
            if pages.isEmpty {
                finish()
            } else {
                proofPages = pages
                showProofs = true
            }
        } catch {
            // Hủy bản nháp vừa tạo (xóa game kéo theo các hint đã tạo) để người dùng thử lại từ bước 3.
            try? await API.deleteDraftGame(id: game.id)
            self.error = AppError.message(for: error)
        }
    }

    private func finish() {
        guard let created else { return }
        dismiss()
        onCreated(created)
    }
}

/// Bản nháp wizard "Giữ nháp": chỉ lưu trên máy này (UserDefaults), theo từng tài khoản.
/// Chứa cả mã proof chưa hash, nên không bao giờ gửi lên server cho đến khi bấm "Tạo game".
struct WizardDraft: Codable {
    var form: GameForm
    var hints: [DraftHint]
    var step: Int
    /// Bản nháp cũ không có trường này → nil.
    var startsAt: Date?
}

enum WizardDraftStore {
    private static var key: String? {
        Supa.currentUserId.map { "createGameDraft.\($0.uuidString.lowercased())" }
    }

    static func load() -> WizardDraft? {
        guard let key, let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WizardDraft.self, from: data)
    }

    static func save(_ draft: WizardDraft) {
        guard let key, let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        DraftHintImages.removeAll()
        guard let key else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Ảnh của hint nháp: lưu file JPEG trên máy (Application Support/HintDrafts), không để trong
/// UserDefaults vì quá nặng. Xóa hết khi bản nháp bị xóa hoặc game đã được tạo.
enum DraftHintImages {
    private static var dir: URL {
        URL.applicationSupportDirectory.appending(path: "HintDrafts", directoryHint: .isDirectory)
    }

    static func url(_ name: String) -> URL { dir.appending(path: name) }

    static func save(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.lowercased()).jpg"
        try data.write(to: url(name), options: .atomic)
        return name
    }

    static func load(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }

    static func removeAll() { try? FileManager.default.removeItem(at: dir) }
}

/// Chọn / đổi / bỏ ảnh gợi ý cho hint nháp. Ảnh được nén như khối ảnh ở màn sửa hint.
private struct DraftHintPhoto: View {
    @Binding var imageFile: String?
    @Binding var error: String?
    @State private var item: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: FM.s) {
            if let imageFile, let image = UIImage(contentsOfFile: DraftHintImages.url(imageFile).path()) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: FM.radiusSmall, style: .continuous))
                    .accessibilityLabel(Text("Ảnh gợi ý"))
            }
            HStack {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(imageFile == nil ? "Thêm ảnh (không bắt buộc)" : "Đổi ảnh", systemImage: "photo")
                }
                .foregroundStyle(Color.fmAccent)
                Spacer()
                if loading {
                    ProgressView()
                } else if imageFile != nil {
                    Button(role: .destructive) { withAnimation { imageFile = nil } } label: {
                        Label("Bỏ ảnh", systemImage: "trash").labelStyle(.iconOnly)
                    }
                    .foregroundStyle(Color.fmDanger)
                    .accessibilityLabel(Text("Bỏ ảnh"))
                }
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            loading = true
            Task {
                defer { loading = false; item = nil }
                do {
                    guard let data = try await picked.loadTransferable(type: Data.self), let image = UIImage(data: data),
                          let jpeg = ImageCompressor.jpeg(from: image, maxLongEdge: 2048, maxBytes: 1_500_000)
                    else { throw API.APIError.compressionFailed }
                    let name = try DraftHintImages.save(jpeg)
                    withAnimation { imageFile = name }
                } catch { self.error = AppError.message(for: error) }
            }
        }
    }
}

/// Bước 3: mọi ghim đáp án (đánh số theo thứ tự) nối thành lộ trình, cộng khu vực công khai nếu có.
private struct ReviewMap: View {
    let hints: [DraftHint]
    let area: CLLocationCoordinate2D?
    let onSelect: (DraftHint) -> Void
    @State private var selected: Int?

    private var pinned: [(order: Int, hint: DraftHint, pin: CLLocationCoordinate2D)] {
        hints.enumerated().compactMap { i, h in h.pin.map { (i + 1, h, $0) } }
    }

    var body: some View {
        Map(initialPosition: .automatic, selection: $selected) {
            if let area {
                MapCircle(center: area, radius: 1000)
                    .foregroundStyle(Color.fmAccent.opacity(0.12))
                    .stroke(Color.fmAccent.opacity(0.6), lineWidth: 1.5)
            }
            if pinned.count > 1 {
                MapPolyline(coordinates: pinned.map(\.pin))
                    .stroke(.fmAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
            }
            ForEach(pinned, id: \.order) { p in
                Marker(p.hint.title.trimmedOrNil ?? String(localized: "Hint \(p.order)"),
                       monogram: Text("\(p.order)"), coordinate: p.pin)
                    .tint(.fmAccent)
                    .tag(p.order)
            }
        }
        .mapControls { MapCompass() }
        .onChange(of: selected) { _, order in
            guard let order, let p = pinned.first(where: { $0.order == order }) else { return }
            selected = nil
            onSelect(p.hint)
        }
    }
}

/// Thanh tiến trình 3 bước ở đầu wizard.
private struct StepIndicator: View {
    let current: CreateGameView.Step

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CreateGameView.Step.allCases, id: \.self) { s in
                let done = s.rawValue < current.rawValue
                let active = s == current
                VStack(spacing: 6) {
                    Capsule()
                        .fill(s.rawValue <= current.rawValue ? Color.fmAccent : Color.fmBorder)
                        .frame(height: 4)
                    HStack(spacing: 4) {
                        Image(systemName: done ? "checkmark.circle.fill" : "\(s.rawValue + 1).circle\(active ? ".fill" : "")")
                        Text(s.title)
                    }
                    .font(.caption.weight(active ? .semibold : .regular))
                    .foregroundStyle(active || done ? Color.fmAccent : Color.fmTextSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bước \(current.rawValue + 1) trên \(CreateGameView.Step.allCases.count)"))
    }
}

/// A hint being drafted in the wizard; only sent to the server when the hunt is created.
struct DraftHint: Identifiable, Hashable, Codable {
    var id = UUID()
    var title = ""
    var details = ""
    var prize: Double = 0
    /// Thưởng mốc là hiện vật; nil = tiền.
    var prizeItem: String?
    var code = ""
    var latitude: Double?
    var longitude: Double?
    /// Ảnh gợi ý (không bắt buộc): tên file JPEG trong `DraftHintImages`, chỉ tải lên khi tạo game.
    var imageFile: String?

    var pin: CLLocationCoordinate2D? {
        get { latitude.flatMap { lat in longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } } }
        set { latitude = newValue?.latitude; longitude = newValue?.longitude }
    }

    var codeValid: Bool { code.filter { $0.isLetter || $0.isNumber }.count >= 6 }
    var titleValid: Bool { title.trimmedOrNil != nil }
    var isValid: Bool { pin != nil && codeValid && titleValid && (prizeItem.map(PrizeInput.isValidItem) ?? true) }
}

private struct DraftHintRow: View {
    let hint: DraftHint
    let order: Int
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(order)").font(.headline.monospacedDigit())
                .frame(width: 30, height: 30).background(Color.fmAccentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(hint.title.trimmedOrNil ?? String(localized: "Hint \(order)")).font(.fmHeadline)
                    .foregroundStyle(Color.fmText)
                if let d = hint.details.trimmedOrNil {
                    Text(d).font(.caption).foregroundStyle(Color.fmTextSecondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                        Text(verbatim: ProofPaper.spaced(hint.code)).monospacedDigit()
                    }
                    if hint.imageFile != nil {
                        Image(systemName: "photo").accessibilityLabel(Text("Có ảnh"))
                    }
                    if let prize = Fmt.prize(hint.prize, item: hint.prizeItem, currency: currency) {
                        HStack(spacing: 4) {
                            Image(systemName: "gift")
                            Text(verbatim: prize).monospacedDigit().lineLimit(1)
                        }
                    }
                }
                .font(.caption).foregroundStyle(Color.fmTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Add / edit one drafted hint: title, description, prize, answer pin, proof code.
private struct DraftHintEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: DraftHint
    let order: Int
    let currency: String
    /// Giải tổng bằng tiền; nil khi giải tổng là hiện vật (không giới hạn thưởng mốc).
    let grandPrizeCap: Double?
    let onSave: (DraftHint) -> Void
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case title, details, prize, code }

    var body: some View {
        NavigationStack {
            Form { ThemedRows {
                Section {
                    TextField("Tiêu đề", text: $draft.title)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focus = .details }
                    TextField("Mô tả (không bắt buộc)", text: $draft.details, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focus, equals: .details)
                        .onChange(of: draft.details) { _, d in
                            if d.count > HintDescription.maxLength { draft.details = String(d.prefix(HintDescription.maxLength)) }
                        }
                    DraftHintPhoto(imageFile: $draft.imageFile, error: $error)
                    PrizeFields(label: "Thưởng mốc", amount: $draft.prize, item: $draft.prizeItem, currency: currency)
                } header: {
                    Text("Hint \(order)")
                } footer: {
                    VStack(alignment: .leading, spacing: FM.s) {
                        if overCap, let cap = grandPrizeCap {
                            Label("Thưởng mốc không được lớn hơn giải thưởng tổng (\(Fmt.money(cap, currency: currency))).", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.fmDanger)
                        }
                        Text("Tiêu đề là bắt buộc; mô tả và ảnh không bắt buộc.")
                    }
                }
                Section {
                    PinPickerMap(coordinate: $draft.pin)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Vị trí đáp án")
                } footer: {
                    Text("Vị trí này chỉ hiện cho người chơi sau khi hint được giải.")
                }
                Section {
                    HStack {
                        TextField("Mã in trên tờ giấy", text: $draft.code)
                            .font(.title3.monospacedDigit())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .code)
                            .submitLabel(.done)
                            .onSubmit { focus = nil }
                        Button("Gợi ý mã") { suggest() }.buttonStyle(.bordered)
                    }
                } header: {
                    Text("Mã")
                } footer: {
                    Text("Ít nhất 6 chữ/số. Không phân biệt hoa thường, bỏ qua khoảng trắng và dấu.")
                }
            } }.fmScreen()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Hint \(order)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { onSave(draft); dismiss() }.disabled(!draft.isValid || overCap)
                }
            }
            .onAppear { if draft.code.isEmpty { suggest() } }
            .errorAlert($error)
        }
    }

    private var overCap: Bool { PrizeInput.exceedsCap(amount: draft.prize, item: draft.prizeItem, cap: grandPrizeCap) }

    private func suggest() {
        Task {
            do { draft.code = try await API.generateHintCode() } catch { self.error = AppError.message(for: error) }
        }
    }
}

/// Shared form sections for creating and editing a game (limits mirror the SQL check constraints).
struct GameFormFields: View {
    @Binding var form: GameForm
    /// Chỉ wizard tạo game truyền vào: hẹn giờ bắt đầu ngay khi tạo (sửa game dùng ScheduleSheet).
    var startsAt: Binding<Date?>? = nil
    /// Số người chơi đang có (sửa cài đặt): không cho hạ giới hạn xuống dưới mức này.
    var currentPlayers: Int = 0
    /// Thưởng mốc lớn nhất của các hint (sửa cài đặt): giải thưởng tổng không được thấp hơn mức này.
    var minGrandPrize: Double = 0
    /// Có thưởng mốc bằng tiền: vẫn cần đơn vị tiền tệ dù giải tổng là hiện vật.
    var hasMoneyHintPrize: Bool = false
    @FocusState private var focus: GameFormField?

    private var playerRange: ClosedRange<Int> { max(1, currentPlayers)...GameForm.playerLimit }

    private func clampPlayers() {
        let clamped = min(max(form.maxPlayers, playerRange.lowerBound), playerRange.upperBound)
        if clamped != form.maxPlayers { form.maxPlayers = clamped }
    }

    var body: some View {
        Group {
            Section("Thông tin") {
                TextField("Tiêu đề", text: $form.title)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focus = .description }
                    .onChange(of: form.title) { _, t in if t.count > 120 { form.title = String(t.prefix(120)) } }
                TextField("Mô tả", text: $form.description, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focus, equals: .description)
                AddressField(form: $form, focus: $focus)
                if let startsAt { StartTimeRows(startsAt: startsAt) }
            }
            Section {
                PrizeFields(label: "Giải thưởng tổng", amount: $form.grandPrize, item: $form.grandPrizeItem,
                            currency: form.currency)
                // Giải tổng là hiện vật thì không cần tiền tệ (trừ khi có thưởng mốc bằng tiền).
                if form.grandPrizeItem == nil || hasMoneyHintPrize {
                    Picker("Đơn vị tiền tệ", selection: $form.currency) {
                        Text("VND").tag("VND")
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                    }
                }
            } header: {
                Text("Giải thưởng")
            } footer: {
                VStack(alignment: .leading, spacing: FM.s) {
                    if form.grandPrizeItem == nil && form.grandPrize < minGrandPrize {
                        Label("Giải thưởng tổng không được nhỏ hơn thưởng mốc lớn nhất (\(Fmt.money(minGrandPrize, currency: form.currency))).", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.fmDanger)
                    }
                    Text("Giải thưởng là tiền hoặc hiện vật (tên món quà). Quản trò tự trao thưởng; app chỉ ghi nhận và đánh dấu đã trao.")
                }
            }
            GlobeAreaSection(form: $form, focus: $focus)
            Section {
                HStack(spacing: FM.s) {
                    Text("Tối đa")
                    Spacer()
                    // Gõ số trực tiếp hoặc bấm −/+; ngoài khoảng cho phép thì kéo về giới hạn gần nhất.
                    TextField("0", value: $form.maxPlayers, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .maxPlayers)
                        .multilineTextAlignment(.center)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .frame(width: 56, height: 34)
                        .background(Color.fmSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityLabel(Text("Số người chơi tối đa"))
                    Stepper("Số người chơi tối đa", value: $form.maxPlayers, in: playerRange)
                        .labelsHidden()
                }
                .onChange(of: form.maxPlayers) { clampPlayers() }
                .onChange(of: focus) { if focus != .maxPlayers { clampPlayers() } }
            } header: {
                Text("Người chơi")
            } footer: {
                Text("Tối đa \(GameForm.playerLimit) người. Quản trò và co-host không tính vào giới hạn. Khi đủ người, mã tham gia sẽ không dùng được nữa.")
            }
            Section {
                Toggle("Tự duyệt nếu quá hạn", isOn: $form.autoApproveEnabled)
                if form.autoApproveEnabled {
                    Stepper(value: $form.autoApproveMinutes, in: 1...1440) {
                        Text("Tự duyệt sau \(form.autoApproveMinutes) phút")
                    }
                }
                Stepper(value: $form.uploadWindowSeconds, in: 15...600, step: 15) {
                    Text("Thời hạn chụp ảnh: \(form.uploadWindowSeconds) giây")
                }
                Stepper(value: $form.codeFailsBeforeLock, in: 1...20) {
                    Text("Khóa sau \(form.codeFailsBeforeLock) lần sai liên tiếp")
                }
                Stepper(value: $form.codeLockMinutes, in: 1...120) {
                    Text("Thời gian khóa nhập mã: \(form.codeLockMinutes) phút")
                }
                Toggle("Công khai ảnh người thắng", isOn: $form.publicWinnerPhotos)
            } header: {
                Text("Cài đặt")
            } footer: {
                Text("Ảnh mã được giữ \(GameForm.proofRetentionDays) ngày sau khi game kết thúc, rồi tự động xóa.")
            }
        }
    }
}

enum GameFormField: Hashable { case title, description, prize, areaName, maxPlayers }

/// Công khai / riêng tư. Game công khai cần địa chỉ tìm được trên bản đồ (xem AddressField).
struct GlobeAreaSection: View {
    @Binding var form: GameForm
    var focus: FocusState<GameFormField?>.Binding

    var body: some View {
        Section {
            Picker("Chế độ", selection: $form.isPublic) {
                Text("Công khai").tag(true)
                Text("Riêng tư").tag(false)
            }
            .pickerStyle(.segmented)
            if form.isPublic {
                Picker("Cách tham gia", selection: joinOpen) {
                    Label("Cần mã", systemImage: "number").tag(false)
                    Label("Mở cho mọi người", systemImage: "door.left.hand.open").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } header: {
            Text("Chế độ")
        } footer: {
            if !form.isPublic {
                Text("Game không hiện trên Globe. Chỉ người có mã tham gia bạn gửi mới vào được.")
            } else if !form.isAreaValid {
                Text("Ghim khu vực trên bản đồ hoặc nhập địa chỉ tìm được (mục Thông tin) để công khai game.")
                    .foregroundStyle(Color.fmDanger)
            } else {
                if form.joinOpen == true {
                    Text("Mọi người thấy game trên Globe (khu vực làm tròn ~1 km) và bấm \"Tham gia ngay\" là vào, không cần mã. Giới hạn người chơi vẫn áp dụng.")
                } else {
                    Text("Mọi người thấy tên, trạng thái và khu vực (làm tròn ~1 km) của game trên Globe. Mã tham gia không bao giờ hiện; người chơi vẫn phải xin mã từ bạn.")
                }
            }
        }
    }

    private var joinOpen: Binding<Bool> {
        Binding(get: { form.joinOpen ?? false }, set: { form.joinOpen = $0 })
    }
}

/// Khu vực game: ghim trên bản đồ (app tự đặt tên khu vực bằng reverse geocode trên máy) hoặc gõ
/// địa chỉ (app tự tìm tọa độ và dời ghim tới đó). Tên chỉ gồm phường/quận/thành phố, không có số
/// nhà; server làm tròn tọa độ ~1 km khi hiện trên Globe.
struct AddressField: View {
    enum Lookup: Equatable { case idle, searching, naming, found, notFound }

    @Binding var form: GameForm
    var focus: FocusState<GameFormField?>.Binding
    @State private var geocodeTask: Task<Void, Never>?
    @State private var lookup: Lookup = .idle
    @State private var cameraTarget: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: FM.s) {
            PinPickerMap(coordinate: pin, meters: 4000,
                         emptyPrompt: "Chạm để ghim khu vực game",
                         movePrompt: "Chạm hoặc kéo ghim để đổi khu vực",
                         pinLabel: "Ghim khu vực game",
                         cameraTarget: cameraTarget)
            HStack {
                TextField("Địa chỉ (vd. Phú Nhuận, TP.HCM)", text: Binding(
                    get: { form.areaName ?? "" },
                    set: { new in
                        let v = String(new.prefix(80))
                        guard v != (form.areaName ?? "") else { return }
                        form.areaName = v
                        locate(v)
                    }))
                    .focused(focus, equals: .areaName)
                    .submitLabel(.done)
                    .onSubmit { focus.wrappedValue = nil }
                if lookup == .searching || lookup == .naming { ProgressView() }
            }
            if lookup == .naming {
                Text("Đang tìm tên địa điểm…")
                    .font(.caption).foregroundStyle(Color.fmTextSecondary)
            } else if lookup == .notFound && form.isPublic {
                Text("Không tìm thấy địa chỉ này trên bản đồ. Thử ghi rõ hơn hoặc ghim trên bản đồ.")
                    .font(.caption).foregroundStyle(Color.fmDanger)
            }
        }
        .padding(.vertical, FM.xs)
        .onChange(of: form.isPublic) { _, isPublic in
            // Bật công khai cho game đã có địa chỉ nhưng chưa có tọa độ.
            if isPublic, form.areaLat == nil, let name = form.areaName?.trimmedOrNil { locate(name) }
        }
    }

    /// Ghim do người dùng đặt: lưu tọa độ rồi đặt tên khu vực từ tọa độ đó.
    private var pin: Binding<CLLocationCoordinate2D?> {
        Binding(
            get: { form.areaLat.flatMap { lat in form.areaLng.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } } },
            set: { c in
                form.areaLat = c?.latitude; form.areaLng = c?.longitude
                if let c { name(c) }
            })
    }

    /// Reverse geocode (trên máy): phường · quận · thành phố.
    private func name(_ c: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        focus.wrappedValue = nil
        lookup = .naming
        geocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(300)) // a drag ends with several updates
            guard !Task.isCancelled else { return }
            let mark = try? await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
            guard !Task.isCancelled else { return }
            if let mark, let text = Self.areaName(mark) { form.areaName = text }
            lookup = .found // the pin stands even if no name was found; the host can type one
        }
    }

    static func areaName(_ m: CLPlacemark) -> String? {
        var parts: [String] = []
        for p in [m.subLocality, m.subAdministrativeArea ?? m.locality, m.administrativeArea] {
            if let p = p?.trimmedOrNil, !parts.contains(p) { parts.append(p) }
        }
        if parts.isEmpty, let country = m.country?.trimmedOrNil { parts = [country] } // e.g. pin in open country
        let text = parts.prefix(3).joined(separator: ", ")
        return text.isEmpty ? nil : String(text.prefix(80))
    }

    /// Tìm tọa độ từ địa chỉ (chờ người dùng ngừng gõ 0,6 giây) và dời ghim + bản đồ tới đó.
    private func locate(_ name: String) {
        geocodeTask?.cancel()
        guard let query = name.trimmedOrNil else {
            form.areaLat = nil; form.areaLng = nil; lookup = .idle
            return
        }
        lookup = .searching
        geocodeTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let mark = try? await CLGeocoder().geocodeAddressString(query).first
            guard !Task.isCancelled else { return }
            if let c = mark?.location?.coordinate {
                form.areaLat = c.latitude; form.areaLng = c.longitude; lookup = .found
                cameraTarget = c
            } else {
                form.areaLat = nil; form.areaLng = nil; lookup = .notFound
            }
        }
    }
}

/// "Thời gian" trong mục Thông tin của wizard: bật hẹn giờ rồi chọn ngày giờ (chỉ tương lai).
struct StartTimeRows: View {
    @Binding var startsAt: Date?

    var body: some View {
        Toggle("Hẹn giờ bắt đầu", isOn: Binding(
            get: { startsAt != nil },
            set: { startsAt = $0 ? (startsAt ?? Self.defaultStart()) : nil }))
        if let at = startsAt {
            VStack(alignment: .leading, spacing: FM.xs) {
                DatePicker("Thời gian", selection: Binding(get: { at }, set: { startsAt = $0 }),
                           in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Text(at > Date() ? "Game tự bắt đầu lúc \(Fmt.dateTime(at)) (trễ tối đa 1 phút)."
                                 : "Thời gian bắt đầu phải ở tương lai.")
                    .font(.caption)
                    .foregroundStyle(at > Date() ? Color.fmTextSecondary : Color.fmDanger)
            }
        }
    }

    /// Mặc định: tròn giờ kế tiếp sau 1 tiếng nữa.
    static func defaultStart() -> Date {
        let next = Date().addingTimeInterval(3600)
        return Calendar.current.dateInterval(of: .hour, for: next)?.end ?? next
    }
}
