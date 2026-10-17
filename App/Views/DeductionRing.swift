import SwiftUI

/// Ring, "Deduções Provisórias em IRS", total, and what is still deductible.
/// Shared by the iPhone and Mac Summary pages.
struct DeductionHeader: View {
    @EnvironmentObject var model: AppModel
    var totalSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 4) {
            if let summary = model.summary {
                DeductionRing(categories: summary.categories, maximum: model.limits?.maximum)
                    .id("\(summary.year)-\(summary.total)-\(model.limits?.maximum ?? 0)")
                    .padding(.bottom, 14)
            }
            Text("Deduções Provisórias em IRS")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text((model.summary?.total ?? 0).euros)
                .font(.system(size: totalSize, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            if let limits = model.limits, let total = model.summary?.total {
                Text("Pode deduzir mais \(max(0, limits.maximum - total).euros)" + (limits.isDefault ? " (limites padrão)" : ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Open gauge like Apple's (three quarters of a circle, gap at the bottom), split by how much
/// each category contributes. With a maximum, the coloured part is the share of it already
/// reached and the grey track is what is left. Fills in on appear.
struct DeductionRing: View {
    let categories: [CategorySummary]
    var maximum: Int?
    @State private var progress: CGFloat = 0

    private let span: CGFloat = 0.75
    private let width: CGFloat = 22

    private struct Segment: Identifiable {
        let id: String
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }

    private var segments: [Segment] {
        let parts = categories.filter { $0.deduction > 0 }
        let total = parts.reduce(0) { $0 + $1.deduction }
        let scale = CGFloat(max(maximum ?? total, total))
        guard scale > 0 else { return [] }

        // True shares; the coloured length overall stays exact.
        let shares = parts.map { CGFloat($0.deduction) / scale }
        let filled = shares.reduce(0, +)

        // Every category gets a small visible slice (about 4 points of ring), never more than
        // half of the coloured part in total, so big categories stay clearly bigger.
        let ringLength = CGFloat.pi * (170 - width)          // circumference at the stroke centre
        let minimum = min(4 / ringLength, 0.5 * filled / CGFloat(shares.count))
        var widths = shares.map { max($0, minimum) }
        let overflow = widths.reduce(0, +) - filled
        let spare = widths.reduce(0) { $0 + max(0, $1 - minimum) }
        if overflow > 0, spare > 0 {
            widths = widths.map { $0 - overflow * max(0, $0 - minimum) / spare }
        }

        var start: CGFloat = 0
        return zip(parts, widths).map { item, width in
            let end = start + width
            defer { start = end }
            return Segment(id: item.code, start: start, end: end,
                           color: Sector.named(item.code)?.color ?? .secondary)
        }
    }

    private var filled: CGFloat { segments.last?.end ?? 0 }
    private var reached: CGFloat { min(progress, filled) }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: span)
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            ForEach(segments) { s in
                Circle()
                    .trim(from: min(s.start, progress) * span, to: min(s.end, progress) * span)
                    .stroke(s.color, style: StrokeStyle(lineWidth: width, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(135))
        .frame(width: 170, height: 170)
        .onAppear {
            progress = 0
            withAnimation(.easeOut(duration: 1.2)) { progress = 1 }
        }
    }
}
