import GlassDeckKit
import SwiftUI

/// A filled history curve. Values are fractions in `0...1`, oldest first.
struct Sparkline: View {
    let values: [Double]
    let gradient: LinearGradient
    /// Colour of the dot on the latest value; no dot when `nil`.
    var accent: Color?
    var lineWidth: CGFloat = 2

    private static let dotSize: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
                // A faint line at half scale: without one the curve has no
                // scale at all, and a flat line at 10% looked like one at 60%.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height / 2))
                }
                .stroke(.primary.opacity(0.12), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

                if points.count > 1 {
                    curve(points)
                        .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    filledCurve(points, height: proxy.size.height)
                        .fill(
                            LinearGradient(
                                colors: [.primary.opacity(0.16), .primary.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    if let accent, let last = points.last {
                        Circle()
                            .fill(accent)
                            .frame(width: Self.dotSize, height: Self.dotSize)
                            .position(last)
                    }
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let inset = accent == nil ? 0 : Self.dotSize / 2
        let step = (size.width - inset) / CGFloat(values.count - 1)
        // A floor on the vertical span keeps a flat idle line from hugging the border.
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(value.clamped01) * (size.height - lineWidth - inset * 2) - lineWidth / 2 - inset
            )
        }
    }

    /// Catmull-Rom style smoothing via mid-point quadratics: cheap, and it keeps
    /// the curve inside the value range (no cubic overshoot above 100%).
    private func curve(_ points: [CGPoint]) -> Path {
        Path { path in
            path.move(to: points[0])
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
            }
            path.addLine(to: points[points.count - 1])
        }
    }

    private func filledCurve(_ points: [CGPoint], height: CGFloat) -> Path {
        var path = curve(points)
        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: height))
        path.addLine(to: CGPoint(x: points[0].x, y: height))
        path.closeSubpath()
        return path
    }
}
