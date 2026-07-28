import SwiftUI

struct AudioWaveformView: View {
    let samples: [Double]
    var activeFraction: Double = 1
    var activeColor: Color = .red
    var inactiveColor: Color = .secondary

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }

            // Voice Memos keeps a fine, stable time scale instead of stretching
            // a small number of meter readings into widely spaced thick bars.
            let preferredSpacing = 3.2
            let count = max(1, Int(size.width / preferredSpacing))
            let visibleSamples = Array(samples.suffix(count))
            let leadingSilenceCount = max(0, count - visibleSamples.count)
            let spacing = size.width / Double(count)
            let lineWidth = max(0.8, min(1.1, spacing * 0.32))

            for index in 0..<count {
                let x = (Double(index) + 0.5) * spacing
                let sampleIndex = index - leadingSilenceCount
                let sample = sampleIndex >= 0 ? visibleSamples[sampleIndex] : 0
                let normalized = max(0.012, min(1, sample))
                let height = max(1.4, size.height * normalized * 0.86)
                var path = Path()
                path.move(to: CGPoint(x: x, y: (size.height - height) / 2))
                path.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))

                let fraction = Double(index) / Double(max(count - 1, 1))
                context.stroke(
                    path,
                    with: .color(fraction <= activeFraction ? activeColor : inactiveColor.opacity(0.35)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
        .accessibilityHidden(true)
    }
}
