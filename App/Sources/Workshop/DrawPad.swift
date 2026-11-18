import SwiftUI
import SquishWorkshop

/// A pad to draw on with a finger: the squishy's own shape, or its face (Workshop Pro).
/// Anything drawn works. There is no wrong drawing and no error.
struct DrawPad: View {
    enum Kind { case shape, face }

    let kind: Kind
    /// For a face: the squishy that is drawn on.
    var design: WorkshopDesign?
    /// The strokes, 0...1 across the pad, and how fat the line was as a share of the pad.
    let done: ([[WorkshopPoint]], Double) -> Void
    let cancel: () -> Void

    @State private var strokes: [[WorkshopPoint]] = []
    @State private var current: [WorkshopPoint] = []
    @State private var padSide: CGFloat = 340

    /// The spec's 24 pt fat line for a shape; a face is drawn with the line its eyes and mouth have.
    private func lineWidth(_ side: CGFloat) -> CGFloat {
        kind == .shape ? 24 : max(3, side * CGFloat(WorkshopDesign.bodyShare) * 0.035)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                IconButton(system: "xmark", action: cancel)
                Spacer()
                IconButton(system: "arrow.uturn.backward") {
                    if !strokes.isEmpty { strokes.removeLast() }
                }
            }
            GeometryReader { geo in
                let side = max(100, min(geo.size.width, geo.size.height))
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(Color.white)
                    if kind == .face, let design {
                        WorkshopSquishyView(design: design, showsFace: false).frame(width: side, height: side)
                    }
                    DrawnStrokes(strokes: strokes + [current])
                        .stroke(Theme.plum, style: StrokeStyle(lineWidth: lineWidth(side), lineCap: .round, lineJoin: .round))
                }
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            padSide = side
                            current.append(WorkshopPoint(x: min(1, max(0, Double(value.location.x / side))),
                                                         y: min(1, max(0, Double(value.location.y / side)))))
                        }
                        .onEnded { _ in
                            if !current.isEmpty { strokes.append(current) }
                            current = []
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Draw"))
                .accessibilityIdentifier("ws-pad")
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            Button {
                done(strokes, Double(lineWidth(padSide) / padSide))
            } label: {
                Label("Done", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityIdentifier("ws-pad-done")
        }
        .padding(16)
        .background(Theme.marshmallow.ignoresSafeArea())
    }
}
