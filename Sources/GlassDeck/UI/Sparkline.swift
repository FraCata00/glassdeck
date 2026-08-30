import SwiftUI

/// A filled history curve. Values are fractions in `0...1`, oldest first.
struct Sparkline: View {
    let values: [Double]
    let gradient: LinearGradient
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack {
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
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        // A floor on the vertical span keeps a flat idle line from hugging the border.
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(value.clamped01) * (size.height - lineWidth) - lineWidth / 2
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

private extension Double {
    var clamped01: Double { isFinite ? Swift.min(1, Swift.max(0, self)) : 0 }
}
