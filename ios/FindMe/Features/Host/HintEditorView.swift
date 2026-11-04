import MapKit
import PhotosUI
import SwiftUI

struct ProofSheetInfo: Identifiable {
    let id = UUID()
    let code: String
    let order: Int
    let title: String?
}

/// F-04: create a hint via rpc create_hint (code hashed server-side).
struct NewHintView: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var prize: Double = 0
    @State private var prizeItem: String?
    @State private var order = 1
    @State private var code = ""
    @State private var pin: CLLocationCoordinate2D?
    @State private var working = false
    @State private var error: String?
    @State private var proofSheet: ProofSheetInfo?
    private static let maxDetails = HintDescription.maxLength

    var body: some View {
        NavigationStack {
            Form { ThemedRows {
                Section("Hint") {
                    TextField("Tiêu đề", text: $title)
                    TextField("Mô tả (không bắt buộc)", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                        .onChange(of: details) { if details.count > Self.maxDetails { details = String(details.prefix(Self.maxDetails)) } }
                    Stepper(value: $order, in: 1...999) { Text("Thứ tự: \(order)") }
                    PrizeFields(label: "Thưởng mốc", amount: $prize, item: $prizeItem, currency: vm.game?.currency ?? "VND")
                    if prizeTooHigh {
                        Label("Thưởng mốc không được lớn hơn giải thưởng tổng (\(Fmt.money(vm.game?.grandPrize ?? 0, currency: vm.game?.currency ?? "VND"))).", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.fmDanger)
                            .font(.footnote)
                    }
                }
                Section {
                    PinPickerMap(coordinate: $pin)
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Vị trí đáp án")
                } footer: {
                    Text("Vị trí này chỉ hiện cho người chơi sau khi hint được giải.")
                }
                Section {
                    HStack {
                        TextField("Mã in trên tờ giấy", text: $code)
                            .font(.title3.monospacedDigit())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Gợi ý mã") { suggest() }.buttonStyle(.bordered)
                    }
                } header: {
                    Text("Mã")
                } footer: {
                    Text("Ít nhất 6 chữ/số. Không phân biệt hoa thường, bỏ qua khoảng trắng và dấu.")
                }
            } }.fmScreen()
            .navigationTitle("Thêm hint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") { create() }.disabled(!valid || working)
                }
            }
            .disabled(working)
            .onAppear {
                order = (vm.hostHints.map(\.hintOrder).max() ?? 0) + 1
                if code.isEmpty { suggest() }
            }
            .sheet(item: $proofSheet, onDismiss: { dismiss() }) { info in
                ProofSheetView(code: info.code, hintOrder: info.order, hintTitle: info.title, gameTitle: vm.game?.title ?? "")
            }
            .errorAlert($error)
        }
    }

    private var normalizedCount: Int { code.filter { $0.isLetter || $0.isNumber }.count }
    private var valid: Bool { pin != nil && normalizedCount >= 6 && !title.trimmingCharacters(in: .whitespaces).isEmpty && prizeValid }
    private var prizeTooHigh: Bool {
        PrizeInput.exceedsCap(amount: prize, item: prizeItem, cap: vm.game.flatMap { $0.grandPrizeItem == nil ? $0.grandPrize : nil })
    }
    private var prizeValid: Bool { !prizeTooHigh && (prizeItem.map(PrizeInput.isValidItem) ?? true) }

    private func suggest() {
        Task {
            do { code = try await API.generateHintCode() } catch { self.error = AppError.message(for: error) }
        }
    }

    private func create() {
        guard let pin else { return }
        working = true
        Task {
            defer { working = false }
            do {
                let t = title.trimmingCharacters(in: .whitespaces)
                _ = try await API.createHint(gameId: vm.gameId, order: order, code: code,
                                             lat: pin.latitude, lng: pin.longitude, prize: prize,
                                             prizeItem: prizeItem,
                                             title: t.isEmpty ? nil : t, description: details.trimmedOrNil)
                await vm.refresh()
                proofSheet = ProofSheetInfo(code: code, order: order, title: t.isEmpty ? nil : t)
            } catch { self.error = AppError.message(for: error) }
        }
    }
}

/// Edit an existing hint (title/prize/pin), reset its code, and author its items (F-05/F-06/F-07).
struct HintEditorView: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    let hintId: UUID
    @State private var title = ""
    @State private var details = ""
    @State private var prize: Double = 0
    @State private var prizeItem: String?
    @State private var pin: CLLocationCoordinate2D?
    @State private var items: [HostHintItem] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var working = false
    @State private var editingItem: ItemEditTarget?
    @State private var showNewCode = false
    @State private var confirmDelete = false
    @State private var code: String?
    @State private var codeLoaded = false
    @State private var proofSheet: ProofSheetInfo?
    @State private var viewingImage: HintImageTarget?
    private static let maxDetails = HintDescription.maxLength

    private var hint: HostHint? { vm.hostHints.first { $0.id == hintId } }
    private var isLastHint: Bool { vm.hostHints.count <= 1 }
    /// Thêm/xóa/đổi thứ tự hint: chỉ trước khi bắt đầu.
    private var gameEditable: Bool { vm.game?.status.isEditable ?? false }
    /// Sửa tiêu đề, mô tả, thưởng và khối gợi ý: trước khi bắt đầu, hoặc khi đang diễn ra mà hint
    /// chưa giải (khớp hint_is_editable, 20261103001400 + 20261103001600). Vị trí đáp án và mã proof
    /// chỉ sửa được trước khi bắt đầu (gameEditable).
    private var editable: Bool {
        gameEditable || (vm.game?.status == .live && hint?.revealedAt == nil)
    }
    private var editingLive: Bool { editable && !gameEditable }
    private var prizeTooHigh: Bool {
        PrizeInput.exceedsCap(amount: prize, item: prizeItem, cap: vm.game.flatMap { $0.grandPrizeItem == nil ? $0.grandPrize : nil })
    }
    private var prizeValid: Bool { !prizeTooHigh && (prizeItem.map(PrizeInput.isValidItem) ?? true) }

    var body: some View {
        Form { ThemedRows {
            if let hint {
                Section("Hint \(hint.hintOrder)") {
                    TextField("Tiêu đề", text: $title)
                    TextField("Mô tả (không bắt buộc)", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                        .onChange(of: details) { if details.count > Self.maxDetails { details = String(details.prefix(Self.maxDetails)) } }
                    PrizeFields(label: "Thưởng mốc", amount: $prize, item: $prizeItem, currency: vm.game?.currency ?? "VND")
                    if prizeTooHigh {
                        Label("Thưởng mốc không được lớn hơn giải thưởng tổng (\(Fmt.money(vm.game?.grandPrize ?? 0, currency: vm.game?.currency ?? "VND"))).", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.fmDanger)
                            .font(.footnote)
                    }
                }
                .disabled(!editable)
                Section("Vị trí đáp án") {
                    PinPickerMap(coordinate: $pin, locked: !gameEditable).listRowInsets(EdgeInsets())
                }
                codeSection(hint)
                if hint.revealedAt != nil {
                    Section {
                        Label("Hint đã được giải nên không sửa được nữa.", systemImage: "lock")
                            .foregroundStyle(Color.fmTextSecondary)
                    }
                }
                itemsSection
                if gameEditable {
                    Section {
                        Button("Xóa hint", role: .destructive) { confirmDelete = true }
                            .disabled(isLastHint)
                    } footer: {
                        if isLastHint {
                            Text("Mỗi game cần ít nhất một hint. Thêm hint khác trước khi xóa hint này.")
                        }
                    }
                }
                // Nút lưu luôn ở cuối màn.
                if editable {
                    Section {
                        Button("Lưu thay đổi") { save(hint) }
                            .disabled(!dirty(hint) || working || !prizeValid || title.trimmingCharacters(in: .whitespaces).isEmpty)
                    } footer: {
                        if editingLive {
                            Text("Game đang diễn ra: vị trí đáp án và mã đã bị khóa. Người chơi thấy thay đổi ngay khi bạn lưu.")
                        }
                    }
                }
            } else {
                Text("Hint không còn tồn tại.")
            }
        } }.fmScreen()
        .navigationTitle(hint?.title ?? String(localized: "Hint"))
        .disabled(working)
        .task { await load() }
        .sheet(item: $editingItem, onDismiss: { Task { await reloadItems() } }) { target in
            HintItemEditor(gameId: vm.gameId, hintId: hintId, target: target, nextOrder: (items.map(\.itemOrder).max() ?? 0) + 1)
        }
        .sheet(item: $proofSheet) { info in
            ProofSheetView(code: info.code, hintOrder: info.order, hintTitle: info.title, gameTitle: vm.game?.title ?? "")
        }
        .fullScreenCover(item: $viewingImage) { HintImageViewer(path: $0.id) }
        .sheet(isPresented: $showNewCode, onDismiss: { Task { await reloadCode() } }) {
            NewCodeSheet(hintId: hintId, hintOrder: hint?.hintOrder ?? 0, hintTitle: hint?.title,
                         gameTitle: vm.game?.title ?? "")
        }
        .confirmationDialog("Xóa hint này?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xóa", role: .destructive) {
                act {
                    try await API.deleteHint(id: hintId)
                    await vm.refresh()
                    dismiss()
                }
            }
        }
        .errorAlert($error)
    }

    @ViewBuilder private var itemsSection: some View {
        Section {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    if editable { editingItem = .existing(item) } else if let p = item.imagePath { viewingImage = HintImageTarget(id: p) }
                } label: { ItemRow(item: item, onViewImage: { viewingImage = HintImageTarget(id: $0) }) }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        if editable {
                            Button("Xóa", role: .destructive) {
                                act { try await API.deleteHintItem(id: item.id); await reloadItems() }
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if editable && index > 0 {
                            Button("Lên") { act { try await swap(item, items[index - 1]) } }.tint(.fmInfo)
                        }
                        if editable && index < items.count - 1 {
                            Button("Xuống") { act { try await swap(item, items[index + 1]) } }.tint(.fmAccent)
                        }
                    }
            }
            if editable {
                Menu {
                    Button("Văn bản", systemImage: "text.alignleft") { editingItem = .new(.text) }
                    Button("Ảnh", systemImage: "photo") { editingItem = .new(.image) }
                    Button("Vùng bản đồ", systemImage: "map") { editingItem = .new(.map) }
                } label: { Label("Thêm khối gợi ý", systemImage: "plus") }
            }
        } header: {
            Text("Khối gợi ý (\(items.count))")
        } footer: {
            if editable { Text("Chạm để sửa, vuốt để xóa hoặc đổi thứ tự.") }
        }
    }

    @ViewBuilder private func codeSection(_ hint: HostHint) -> some View {
        Section {
            HStack {
                if let code {
                    Text(code)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .textSelection(.enabled)
                    Spacer()
                    FMCopyButton(value: code, toast: "Đã copy mã", font: .body)
                        .buttonStyle(.borderless)
                } else if codeLoaded {
                    Text("Không xem được mã này").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            if let code {
                Button("In tờ mã", systemImage: "printer") {
                    proofSheet = ProofSheetInfo(code: code, order: hint.hintOrder, title: hint.title)
                }
            }
            if gameEditable { Button("Đặt mã mới", systemImage: "arrow.triangle.2.circlepath") { showNewCode = true } }
        } header: {
            Text("Mã")
        } footer: {
            if codeLoaded && code == nil {
                Text("Hint này được tạo trước khi app lưu mã để xem lại. Đặt mã mới nếu bạn cần xem hoặc in lại tờ giấy.")
            } else {
                Text("Chỉ ban quản trò thấy mã này. Người chơi phải tìm tờ giấy để có mã.")
            }
        }
    }

    private func reloadCode() async {
        // Không hiện alert: server chưa có bảng hint_codes (chưa chạy migration) thì chỉ coi như chưa xem được mã.
        do { code = try await API.hintCode(hintId: hintId) } catch { code = nil }
        codeLoaded = true
    }

    private func dirty(_ h: HostHint) -> Bool {
        (title.isEmpty ? nil : title) != h.title || details.trimmedOrNil != h.description || prize != h.prize
            || prizeItem?.trimmedOrNil != h.prizeItem || (prizeItem != nil) != (h.prizeItem != nil)
            || (gameEditable && pin.map { locationChanged($0, h) } == true)
    }

    /// Lệch < ~1 cm (1e-7 độ) coi như không đổi: tránh sai số làm tròn khi đi qua JSON.
    private func locationChanged(_ c: CLLocationCoordinate2D, _ h: HostHint) -> Bool {
        abs(c.latitude - h.answerLat) > 1e-7 || abs(c.longitude - h.answerLng) > 1e-7
    }

    private func load() async {
        guard !loaded, let h = hint else { return }
        title = h.title ?? ""
        details = h.description ?? ""
        prize = h.prize
        prizeItem = h.prizeItem
        pin = CLLocationCoordinate2D(latitude: h.answerLat, longitude: h.answerLng)
        loaded = true
        async let c: Void = reloadCode()
        await reloadItems()
        await c
    }

    private func reloadItems() async {
        do { items = try await API.hintItems(hintId: hintId) } catch { self.error = AppError.message(for: error) }
    }

    private func swap(_ a: HostHintItem, _ b: HostHintItem) async throws {
        let (oa, ob) = (a.itemOrder, b.itemOrder == a.itemOrder ? a.itemOrder + 1 : b.itemOrder)
        try await API.setItemOrder(id: a.id, order: ob)
        try await API.setItemOrder(id: b.id, order: oa)
        await reloadItems()
    }

    private func save(_ h: HostHint) {
        let t = title.trimmingCharacters(in: .whitespaces)
        // Chỉ gửi vị trí khi game chưa bắt đầu và ghim thật sự được kéo đi (khi live server khóa vị trí).
        let moved = gameEditable ? pin.flatMap { locationChanged($0, h) ? $0 : nil } : nil
        act {
            try await API.updateHint(id: h.id, patch: .init(title: t.isEmpty ? nil : t, description: details.trimmedOrNil,
                                                            prize: prize, prizeItem: prizeItem,
                                                            answerLat: moved?.latitude, answerLng: moved?.longitude))
            vm.showBanner(String(localized: "Đã lưu hint"), success: true)
            await vm.refresh()
            await reloadItems()  // map centers are regenerated by the DB when the pin moves
        }
    }

    private func act(_ work: @escaping () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do { try await work() } catch { self.error = AppError.message(for: error) }
        }
    }
}

private struct ItemRow: View {
    let item: HostHintItem
    var onViewImage: (String) -> Void = { _ in }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.type.icon).frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                switch item.type {
                case .text: Text(item.textContent ?? "").lineLimit(2)
                case .image: Text("Ảnh")
                case .map: Text("Vùng bản đồ bán kính \(item.mapRadiusM ?? 0) m")
                }
                Text(item.revealAfterMinutes.map { String(localized: "Mở sau \($0) phút") } ?? String(localized: "Mở ngay"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if item.type == .image, let path = item.imagePath {
                Spacer(minLength: FM.s)
                Button { onViewImage(path) } label: {
                    SignedImage(bucket: "hint-media", path: path, contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Xem ảnh"))
            }
        }
    }
}

struct HintImageTarget: Identifiable { let id: String }

/// Ảnh của khối gợi ý ở toàn màn hình: chụm để phóng to, chạm đúp để phóng to/thu nhỏ.
struct HintImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let path: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            SignedImage(bucket: "hint-media", path: path)
                .scaleEffect(scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(MagnifyGesture()
                    .onChanged { scale = max(1, min(lastScale * $0.magnification, 5)) }
                    .onEnded { _ in lastScale = scale })
                .onTapGesture(count: 2) {
                    withAnimation { scale = scale > 1 ? 1 : 2.5 }
                    lastScale = scale
                }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.2), in: Circle())
            }
            .padding(FM.pad)
            .accessibilityLabel(Text("Đóng"))
        }
    }
}

extension HintItemType {
    var icon: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .map: "map"
        }
    }
}

enum ItemEditTarget: Identifiable {
    case new(HintItemType)
    case existing(HostHintItem)
    var id: String {
        switch self {
        case .new(let t): "new-\(t.rawValue)"
        case .existing(let i): i.id.uuidString
        }
    }
}

/// Text / image / map block editor with optional "mở sau X phút".
struct HintItemEditor: View {
    @Environment(GameViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    let gameId: UUID
    let hintId: UUID
    let target: ItemEditTarget
    let nextOrder: Int

    @State private var text = ""
    @State private var imagePath: String?
    @State private var radius: Double = 300
    @State private var delayed = false
    @State private var minutes = 10
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var working = false
    @State private var error: String?

    private var type: HintItemType {
        switch target {
        case .new(let t): t
        case .existing(let i): i.type
        }
    }

    var body: some View {
        NavigationStack {
            Form { ThemedRows {
                switch type {
                case .text:
                    Section("Nội dung") {
                        TextField("Nội dung gợi ý", text: $text, axis: .vertical).lineLimit(4...12)
                    }
                case .image:
                    Section("Ảnh") {
                        if let imagePath {
                            SignedImage(bucket: "hint-media", path: imagePath)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        let hasImage = imagePath != nil
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(hasImage ? "Đổi ảnh" : "Chọn ảnh", systemImage: "photo.on.rectangle")
                        }
                        if uploading { ProgressView("Đang tải ảnh…") }
                    }
                case .map:
                    Section {
                        Slider(value: $radius, in: 20...5000, step: 10)
                        Stepper(value: $radius, in: 20...50000, step: 10) { Text("Bán kính: \(Int(radius)) m") }
                    } header: {
                        Text("Vùng bản đồ")
                    } footer: {
                        Text("Tâm vùng được máy chủ dịch lệch ngẫu nhiên để không lộ đáp án; vị trí thật vẫn nằm trong vòng tròn.")
                    }
                }
                Section {
                    Toggle("Hẹn giờ mở", isOn: $delayed)
                    if delayed {
                        Stepper(value: $minutes, in: 1...1440) { Text("Mở sau \(minutes) phút") }
                    }
                } footer: {
                    Text("Tính từ lúc hint này được mở cho người chơi.")
                }
            } }.fmScreen()
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Lưu") { save() }.disabled(!valid || working || uploading) }
            }
            .onAppear(perform: populate)
            .onChange(of: photoItem) { _, item in if let item { upload(item) } }
            .errorAlert($error)
        }
    }

    private var valid: Bool {
        switch type {
        case .text: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: imagePath != nil
        case .map: radius >= 20
        }
    }

    private func populate() {
        guard case .existing(let i) = target else { return }
        text = i.textContent ?? ""
        imagePath = i.imagePath
        radius = Double(i.mapRadiusM ?? 300)
        delayed = i.revealAfterMinutes != nil
        minutes = max(1, i.revealAfterMinutes ?? 10)
    }

    private func upload(_ item: PhotosPickerItem) {
        uploading = true
        Task {
            defer { uploading = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                      let jpeg = ImageCompressor.jpeg(from: image, maxLongEdge: 2048, maxBytes: 1_500_000)
                else { throw API.APIError.compressionFailed }
                imagePath = try await API.uploadHintImage(gameId: gameId, data: jpeg)
            } catch { self.error = AppError.message(for: error) }
        }
    }

    private func save() {
        working = true
        Task {
            defer { working = false }
            var draft = HintItemDraft(hintId: hintId, itemOrder: nextOrder, type: type,
                                      textContent: nil, imagePath: nil, mapRadiusM: nil,
                                      revealAfterMinutes: delayed ? minutes : nil)
            switch type {
            case .text: draft.textContent = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .image: draft.imagePath = imagePath
            case .map: draft.mapRadiusM = Int(radius)
            }
            do {
                if case .existing(let i) = target {
                    draft.itemOrder = i.itemOrder
                    try await API.updateHintItem(id: i.id, draft: draft)
                } else {
                    try await API.insertHintItem(draft)
                }
                vm.showBanner(String(localized: "Đã lưu khối gợi ý"), success: true)
                dismiss()
            } catch { self.error = AppError.message(for: error) }
        }
    }
}

extension HintItemType {
    var title: LocalizedStringKey {
        switch self {
        case .text: "Khối văn bản"
        case .image: "Khối ảnh"
        case .map: "Khối bản đồ"
        }
    }
}

/// "Đặt mã mới" via rpc set_hint_code, then shows the proof sheet once.
struct NewCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let hintId: UUID
    let hintOrder: Int
    let hintTitle: String?
    let gameTitle: String
    @State private var code = ""
    @State private var done = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        if done {
            ProofSheetView(code: code, hintOrder: hintOrder, hintTitle: hintTitle, gameTitle: gameTitle)
        } else {
            NavigationStack {
                Form { ThemedRows {
                    HStack {
                        TextField("Mã mới", text: $code)
                            .font(.title3.monospacedDigit())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Gợi ý mã") {
                            Task { do { code = try await API.generateHintCode() } catch { self.error = AppError.message(for: error) } }
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Mã cũ sẽ không còn dùng được. Nhớ thay tờ giấy tại địa điểm.")
                        .font(.footnote).foregroundStyle(.secondary)
                } }.fmScreen()
                .navigationTitle("Đặt mã mới")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Hủy") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lưu") {
                            working = true
                            Task {
                                defer { working = false }
                                do { try await API.setHintCode(hintId: hintId, code: code); done = true }
                                catch { self.error = AppError.message(for: error) }
                            }
                        }
                        .disabled(code.filter { $0.isLetter || $0.isNumber }.count < 6 || working)
                    }
                }
                .errorAlert($error)
            }
        }
    }
}

/// `hints.description` có check ≤ 500 ký tự ở DB.
enum HintDescription {
    static let maxLength = 500
}

extension String {
    /// Bỏ khoảng trắng/xuống dòng ở hai đầu; chuỗi rỗng → nil.
    var trimmedOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
