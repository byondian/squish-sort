import PhotosUI
import SwiftUI
import UIKit
import Vision
import SquishWorkshop

/// A drawing lifted off a photo of paper: its outline is the squishy's mould and its picture goes on the goo.
struct LiftedDrawing {
    let outline: [WorkshopPoint]
    let picture: UIImage
}

/// Turns a photo of a drawing on paper into a squishy's shape and picture. Everything happens on
/// the device. The photo is never written anywhere: only the drawing cut out of it is kept, and
/// only once the squishy is made. A photo with a face in it is never used at all.
enum PhotoDrawing {
    enum Outcome: @unchecked Sendable {
        case drawing(LiftedDrawing)
        /// There is a person in the photo.
        case face
        /// No drawing could be found.
        case nothing
    }

    static let grid = 96
    static let side = 512

    /// The photo as a square of plain pixels, the right way up, cut to its middle.
    private static func pixels(of photo: UIImage) -> (bytes: [UInt8], image: CGImage)? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: side, height: side)
        let square = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let w = photo.size.width, h = photo.size.height
            guard w > 0, h > 0 else { return }
            let k = CGFloat(side) / min(w, h)
            photo.draw(in: CGRect(x: (CGFloat(side) - w * k) / 2, y: (CGFloat(side) - h * k) / 2, width: w * k, height: h * k))
        }
        guard let cg = square.cgImage else { return nil }
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? (bytes, cg) : nil
    }

    /// True when there is a person's face in the picture. When the check itself cannot run, the
    /// answer is yes: a photo that was not checked is never used.
    private static func hasFace(_ image: CGImage) -> Bool {
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return !(request.results ?? []).isEmpty
        } catch {
            #if targetEnvironment(simulator)
            // The simulator on a build machine has no face model; real devices do.
            return false
            #else
            return true
            #endif
        }
    }

    /// Call off the main thread: it looks at every pixel.
    static func lift(_ photo: UIImage) -> Outcome {
        guard let (bytes, image) = pixels(of: photo) else { return .nothing }
        if hasFace(image) { return .face }
        let n = grid
        // How light each cell is, and its colour.
        var luma = [Double](repeating: 1, count: n * n)
        var colour = [[Double]](repeating: [1, 1, 1], count: n * n)
        for cy in 0..<n {
            for cx in 0..<n {
                let x0 = cx * side / n, x1 = max(x0 + 1, (cx + 1) * side / n)
                let y0 = cy * side / n, y1 = max(y0 + 1, (cy + 1) * side / n)
                var r = 0.0, g = 0.0, b = 0.0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let at = (y * side + x) * 4
                        r += Double(bytes[at]); g += Double(bytes[at + 1]); b += Double(bytes[at + 2])
                    }
                }
                let count = Double((x1 - x0) * (y1 - y0)) * 255
                colour[cy * n + cx] = [r / count, g / count, b / count]
                luma[cy * n + cx] = (0.299 * r + 0.587 * g + 0.114 * b) / count
            }
        }
        let ink = DrawnShape.ink(luma: luma, grid: n)
        let traced = DrawnShape.traced(ink: ink, grid: n)
        guard let box = traced.box else { return .nothing }
        // The paper's own colour, so a page under a yellow lamp still comes out white.
        // Paper is the lighter half of everything that is not ink.
        let plain = (0..<(n * n)).filter { !ink[$0] }.map { luma[$0] }.sorted()
        let middle = plain.isEmpty ? 0 : plain[plain.count / 2]
        var paper = [0.0, 0.0, 0.0]
        var cells = 0.0
        for i in 0..<(n * n) where !ink[i] && luma[i] >= middle {
            for c in 0..<3 { paper[c] += colour[i][c] }
            cells += 1
        }
        paper = paper.map { cells > 0 ? max(0.3, $0 / cells) : 1 }
        // The drawing's square of the photo, stretched to the whole picture the same way its outline was.
        let fit = box.fitted
        var out = [UInt8](repeating: 0, count: side * side * 4)
        for v in 0..<side {
            let sy = Int((fit.y + (Double(v) + 0.5) / Double(side) * fit.side) * Double(side))
            guard sy >= 0, sy < side else { continue }
            for u in 0..<side {
                let sx = Int((fit.x + (Double(u) + 0.5) / Double(side) * fit.side) * Double(side))
                guard sx >= 0, sx < side else { continue }
                let from = (sy * side + sx) * 4, to = (v * side + u) * 4
                // Nearly-white paper becomes clear, so the goo shows through it; pen and felt-tip stay as drawn.
                var rgb = [0.0, 0.0, 0.0]
                for c in 0..<3 { rgb[c] = max(0, min(1, Double(bytes[from + c]) / 255 / paper[c] / 0.9)) }
                let alpha = max(0, min(1, (1 - (rgb.min() ?? 1)) * 3))
                for c in 0..<3 { out[to + c] = UInt8(rgb[c] * alpha * 255) }
                out[to + 3] = UInt8(alpha * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let picture = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return .nothing }
        return .drawing(LiftedDrawing(outline: traced.outline, picture: UIImage(cgImage: picture)))
    }

    /// A felt-pen drawing on a page, for the UI tests (a simulator has no camera).
    static func sample() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 900, height: 1200)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.93, green: 0.90, blue: 0.84, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let body = UIBezierPath(ovalIn: CGRect(x: 250, y: 430, width: 400, height: 340))
            UIColor(red: 0.45, green: 0.80, blue: 0.55, alpha: 1).setFill()
            body.fill()
            let ear = UIBezierPath()
            ear.move(to: CGPoint(x: 300, y: 500)); ear.addLine(to: CGPoint(x: 330, y: 350)); ear.addLine(to: CGPoint(x: 420, y: 440))
            ear.move(to: CGPoint(x: 600, y: 500)); ear.addLine(to: CGPoint(x: 570, y: 350)); ear.addLine(to: CGPoint(x: 480, y: 440))
            UIColor(red: 0.2, green: 0.15, blue: 0.3, alpha: 1).setStroke()
            for path in [body, ear] {
                path.lineWidth = 18
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
            UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 400, y: 600, width: 100, height: 70)).fill()
        }
    }
}

/// The camera, for one photo.
private struct CameraView: UIViewControllerRepresentable {
    let taken: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(taken: taken) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let taken: (UIImage?) -> Void
        init(taken: @escaping (UIImage?) -> Void) { self.taken = taken }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            taken(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { taken(nil) }
    }
}

/// "Use a drawing on paper": a photo from the camera or one picked from the photos, turned into a squishy.
/// It says "Ask a grown-up to help" first, because iOS asks about the camera in words.
struct PhotoDrawingView: View {
    let done: (LiftedDrawing) -> Void
    let cancel: () -> Void

    private enum Step { case ask, working, tryAgain }
    @State private var step = Step.ask
    @State private var camera = false
    @State private var picked: PhotosPickerItem?

    private static let isTest = ProcessInfo.processInfo.arguments.contains("-kidsTestDrawing")
    private var hasCamera: Bool { PhotoDrawingView.isTest || UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                IconButton(system: "xmark", action: cancel)
                Spacer()
            }
            Spacer(minLength: 0)
            switch step {
            case .ask, .tryAgain:
                Image(systemName: step == .ask ? "doc.viewfinder.fill" : "pencil.and.scribble")
                    .font(.system(size: 96, weight: .bold)).foregroundStyle(Theme.bubblegum)
                if step == .tryAgain {
                    Text("Try a drawing!").font(Theme.title(28)).foregroundStyle(Theme.plum)
                        .accessibilityIdentifier("photo-try-again")
                } else {
                    Text("Ask a grown-up to help").font(Theme.title(26)).foregroundStyle(Theme.plum)
                }
                Text("Take a photo of your drawing to turn it into a squishy")
                    .font(Theme.body(17)).foregroundStyle(Theme.plum.opacity(0.75)).multilineTextAlignment(.center)
                HStack(spacing: 28) {
                    if hasCamera {
                        Button {
                            if PhotoDrawingView.isTest { use(PhotoDrawing.sample()) } else { camera = true }
                        } label: { round("camera.fill", Theme.bubblegum) }
                        .buttonStyle(PressSquish())
                        .accessibilityLabel(Text("Take a photo"))
                        .accessibilityIdentifier("photo-camera")
                    }
                    PhotosPicker(selection: $picked, matching: .images) { round("photo.on.rectangle.angled", Theme.sky) }
                        .buttonStyle(PressSquish())
                        .accessibilityLabel(Text("Pick a photo"))
                        .accessibilityIdentifier("photo-pick")
                }
                .padding(.top, 8)
            case .working:
                ProgressView().controlSize(.large).tint(Theme.bubblegum)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.marshmallow.ignoresSafeArea())
        .fullScreenCover(isPresented: $camera) {
            CameraView { image in
                camera = false
                if let image { use(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            step = .working
            Task {
                // The picker hands over a copy of the one photo chosen; the app never sees the library.
                let data = try? await item.loadTransferable(type: Data.self)
                if let data, let image = UIImage(data: data) { use(image) } else { step = .tryAgain }
            }
        }
    }

    private func round(_ icon: String, _ fill: Color) -> some View {
        Image(systemName: icon).font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
            .frame(width: 120, height: 120)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(Color.white, lineWidth: 5))
    }

    private func use(_ photo: UIImage) {
        step = .working
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { PhotoDrawing.lift(photo) }.value
            if case .drawing(let lifted) = outcome { done(lifted) } else { step = .tryAgain }
        }
    }
}
