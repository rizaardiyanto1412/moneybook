import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A receipt photo chosen in the editor, re-encoded as JPEG (max 2400 px) to stay well under the 10 MB limit.
struct PendingReceipt {
    var image: NSImage
    var data: Data
    var mimeType: String

    init?(image: NSImage) {
        guard let jpeg = Self.jpeg(image) else { return nil }
        self.image = image
        data = jpeg
        mimeType = "image/jpeg"
    }

    init?(url: URL) {
        guard let img = NSImage(contentsOf: url) else { return nil }
        self.init(image: img)
    }

    private static func jpeg(_ image: NSImage, maxSide: CGFloat = 2400) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }

    /// Accepts dropped files or raw image data.
    static func load(from providers: [NSItemProvider], completion: @escaping @MainActor (PendingReceipt?) -> Void) {
        guard let p = providers.first else { return }
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                let path = url?.path
                Task { @MainActor in completion(path.flatMap { PendingReceipt(url: URL(fileURLWithPath: $0)) }) }
            }
        } else if p.canLoadObject(ofClass: NSImage.self) {
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                Task { @MainActor in completion(data.flatMap(NSImage.init(data:)).flatMap { PendingReceipt(image: $0) }) }
            }
        }
    }
}

/// Loads a stored receipt through the authenticated API.
struct ReceiptThumbnail: View {
    @Environment(AppModel.self) private var model
    var key: String
    @UIState private var image: NSImage?
    @UIState private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: key) {
            image = await model.receiptImage(key)
            failed = image == nil
        }
    }
}

struct ReceiptViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var image: NSImage?
    var key: String?
    @UIState private var loaded: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let img = image ?? loaded {
                    Image(nsImage: img).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 520, idealWidth: 760, minHeight: 520, idealHeight: 820)
        .task {
            if image == nil, let key { loaded = await model.receiptImage(key) }
        }
    }
}
