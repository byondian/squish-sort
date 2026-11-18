import ReplayKit
import SwiftUI
import UIKit

/// Records a few seconds of the screen (Apple's own recorder, with Apple's own permission prompt)
/// and hands the clip to the iOS share sheet. Nothing is uploaded by the app: the clip stays on
/// the phone unless the player sends it somewhere. Never offered in gentle mode.
@MainActor
final class ClipRecorder: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var busy = false

    var available: Bool { RPScreenRecorder.shared().isAvailable }

    /// Asks to record, then records for `seconds`. `started` runs once recording has begun
    /// (a show starts again from the top there).
    func record(seconds: Double, started: (() -> Void)? = nil) {
        guard !recording, !busy else { return }
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        busy = true
        recorder.startRecording { error in
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false
                guard !failed else { return }
                self.recording = true
                started?()
                try? await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
                self.finish()
            }
        }
    }

    private func finish() {
        guard recording else { return }
        let name = "squish-sort-\(Int(Date().timeIntervalSince1970)).mp4"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        RPScreenRecorder.shared().stopRecording(withOutput: url) { error in
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.recording = false
                if !failed { ClipRecorder.share(url) }
            }
        }
    }

    /// The share sheet, over whatever is on top (the capsule is a full-screen cover).
    private static func share(_ url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}

/// The Share button for a big moment. While the clip is being recorded it turns into the small
/// "Squish Sort" mark that is seen in the clip.
struct ClipControl: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var clips: ClipRecorder
    var seconds: Double = 6
    /// Only the mark, never the button (over a show that is being recorded).
    var markOnly = false
    var onStart: (() -> Void)?

    var body: some View {
        if model.canShareClips {
            if markOnly && !clips.recording {
                EmptyView()
            } else if clips.recording {
                HStack(spacing: 6) {
                    Circle().fill(Theme.bubblegum).frame(width: 9, height: 9)
                    Text(verbatim: "Squish Sort").font(Theme.title(15)).foregroundStyle(Theme.plum)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.9)))
                .accessibilityHidden(true)
            } else {
                Button { clips.record(seconds: seconds, started: onStart) } label: {
                    Label("Share", systemImage: "video.fill").font(Theme.body(14)).foregroundStyle(Theme.plum)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                        .overlay(Capsule().stroke(Theme.plum.opacity(0.15), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .disabled(clips.busy)
                .accessibilityIdentifier("share-clip")
            }
        }
    }
}
