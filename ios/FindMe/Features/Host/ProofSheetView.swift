import SwiftUI
import UIKit

/// One printed proof sheet (one hint).
struct ProofPage: Identifiable, Hashable, Sendable {
    let code: String
    let hintOrder: Int
    let hintTitle: String?
    var id: Int { hintOrder }
}

/// The code is stored only as a bcrypt hash, so it is shown exactly once right after creating/resetting it.
/// Lets the host share or print the proof sheets (one PDF, one A4 page per hint, rendered with ImageRenderer).
struct ProofSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let pages: [ProofPage]
    let gameTitle: String
    @State private var pdfURL: URL?

    init(pages: [ProofPage], gameTitle: String) {
        self.pages = pages.sorted { $0.hintOrder < $1.hintOrder }
        self.gameTitle = gameTitle
    }

    init(code: String, hintOrder: Int, hintTitle: String?, gameTitle: String) {
        self.init(pages: [ProofPage(code: code, hintOrder: hintOrder, hintTitle: hintTitle)], gameTitle: gameTitle)
    }

    var body: some View {
        NavigationStack {
            FMScrollScreen {
                Label(pages.count > 1 ? "Mã chỉ hiển thị một lần. Hãy in hoặc lưu các tờ mã ngay bây giờ."
                                      : "Mã chỉ hiển thị một lần. Hãy in hoặc lưu tờ mã ngay bây giờ.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.fmAccent)
                    .padding()
                    .background(.fmAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                ForEach(pages) { page in
                    ProofPaper(code: page.code, hintOrder: page.hintOrder, hintTitle: page.hintTitle, gameTitle: gameTitle)
                        .frame(width: 320)
                        .shadow(radius: 4)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let pdfURL {
                    HStack {
                        ShareLink(item: pdfURL) {
                            Label("Chia sẻ PDF", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.fmSecondary)
                        Button { print(pdfURL) } label: {
                            Label("In", systemImage: "printer").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.fmPrimary)
                    }
                    .padding(.horizontal, FM.screen).padding(.vertical, FM.s + 2)
                    .background(.bar)
                }
            }
            .navigationTitle("Tờ giấy mã")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } } }
            .task { pdfURL = renderPDF() }
        }
        .interactiveDismissDisabled()
    }

    private var fileName: String {
        pages.count == 1 ? "FindMe-Hint\(pages[0].hintOrder)-proof.pdf" : "FindMe-proofs.pdf"
    }

    private func renderPDF() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)  // A4 @ 72 dpi
        guard !pages.isEmpty, let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for page in pages {
            let renderer = ImageRenderer(content:
                ProofPaper(code: page.code, hintOrder: page.hintOrder, hintTitle: page.hintTitle, gameTitle: gameTitle)
                    .frame(width: box.width, height: box.height)
            )
            renderer.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }

    private func print(_ url: URL) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = pages.count == 1 ? "Find Me! Hint \(pages[0].hintOrder)" : "Find Me! \(gameTitle)"
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}

struct ProofPaper: View {
    let code: String
    let hintOrder: Int
    let hintTitle: String?
    let gameTitle: String

    var body: some View {
        VStack(spacing: 18) {
            Text("Find Me!").font(.title.weight(.black)).foregroundStyle(.fmAccent)
            Text(gameTitle).font(.headline).multilineTextAlignment(.center)
            Text("Hint \(hintOrder)\(hintTitle.map { " · \($0)" } ?? "")").font(.subheadline)
            Spacer(minLength: 8)
            Text("Bạn đã tìm thấy!").font(.title2.weight(.bold))
            Text(Self.spaced(code))
                .font(.system(size: 44, weight: .heavy).monospacedDigit())
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(.vertical, 14).padding(.horizontal, 10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [8, 5])))
            Text("1. Mở app Find Me! và nhập mã này.\n2. Chụp ảnh tờ giấy này trong app trong thời hạn cho phép.\n3. Để lại tờ giấy tại chỗ.")
                .font(.footnote).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    static func spaced(_ code: String) -> String {
        code.count == 8 ? "\(code.prefix(4)) \(code.suffix(4))" : code
    }
}
