import AppKit
import SwiftUI

struct FogMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.appearance = NSAppearance(named: .aqua)
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ThemeCanvas: View {
    var theme: AppTheme
    var glass = false
    var showsOutline = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if glass { FogMaterial() }
            theme.paper.opacity(glass ? 0.87 : 1)
            RadialGradient(colors: [theme.wash.opacity(0.65), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 640)
            if showsOutline {
                Ellipse()
                    .strokeBorder(theme.wash, lineWidth: 5)
                    .frame(width: 360, height: 260)
                    .rotationEffect(.degrees(-25))
                    .offset(x: 98, y: -163)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FogPanel: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(0.67), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

struct InkButton: ButtonStyle {
    @Environment(\.appTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? .white : theme.ink)
            .padding(.horizontal, 17).padding(.vertical, 10)
            .background(prominent ? theme.accent : theme.wash.opacity(0.38), in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.77 : 1) : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ThemeSwatchAnchors: PreferenceKey {
    static let defaultValue: [AppTheme: Anchor<CGRect>] = [:]

    static func reduce(value: inout [AppTheme: Anchor<CGRect>], nextValue: () -> [AppTheme: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct ThemeInkTransition {
    let previousFrame: NSImage
    let destination: AppTheme
    let started = Date()
}

extension NSWindow {
    func captureThemeFrame() -> NSImage? {
        guard let contentView, !contentView.bounds.isEmpty,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return nil }
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        let frame = NSImage(size: contentView.bounds.size)
        frame.addRepresentation(bitmap)
        return frame
    }
}

extension View {
    func themeInkTransition(_ transition: Binding<ThemeInkTransition?>) -> some View {
        modifier(ThemeInkTransitionModifier(transition: transition))
    }
}

private struct ThemeInkTransitionModifier: ViewModifier {
    @Binding var transition: ThemeInkTransition?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(ThemeSwatchAnchors.self) { anchors in
                GeometryReader { geometry in
                    if let transition, let anchor = anchors[transition.destination], !reduceMotion {
                        let swatch = geometry[anchor]
                        ThemeInkReveal(previousFrame: transition.previousFrame, destination: transition.destination,
                                       started: transition.started, origin: CGPoint(x: swatch.midX, y: swatch.midY))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .task(id: transition?.started) {
                guard transition != nil else { return }
                try? await Task.sleep(nanoseconds: ThemeInkReveal.durationNanoseconds)
                guard !Task.isCancelled else { return }
                transition = nil
            }
            .onDisappear { transition = nil }
    }
}

struct ThemeInkReveal: View {
    private static let duration: TimeInterval = 1.05
    static let durationNanoseconds = UInt64(duration * 1_000_000_000)

    let previousFrame: NSImage
    let destination: AppTheme
    let started: Date
    let origin: CGPoint

    var body: some View {
        TimelineView(.animation) { frame in
            let elapsed = min(1, max(0, frame.date.timeIntervalSince(started) / Self.duration))
            let progress = CGFloat(1 - pow(1 - elapsed, 1.25))
            let front = InkSpread(progress: progress, origin: origin)
            ZStack {
                front.stroke(destination.accent.opacity(0.18 * min(1, progress * 15)), lineWidth: 18)
                Image(nsImage: previousFrame)
                    .resizable()
                    .mask {
                        Rectangle().overlay {
                            front.fill(.black).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
            }
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .transaction { $0.animation = nil }
    }
}

// Slightly different radii on each lobe keep the advancing edge uneven.
private struct InkSpread: Shape {
    let progress: CGFloat
    let origin: CGPoint

    func path(in rect: CGRect) -> Path {
        let reach = hypot(max(origin.x, rect.width - origin.x),
                          max(origin.y, rect.height - origin.y)) * 1.25
        let radius = reach * progress
        let lobes: [CGFloat] = [1.07, 0.92, 1.10, 0.96, 1.06, 0.92, 1.07, 0.97, 1.12, 0.93, 1.03]
        let points = lobes.enumerated().map { index, lobe in
            let angle = Double(index) * 2 * .pi / Double(lobes.count)
            return CGPoint(x: origin.x + cos(angle) * radius * lobe,
                           y: origin.y + sin(angle) * radius * lobe)
        }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        var path = Path()
        path.move(to: midpoint(points[points.count - 1], points[0]))
        for (index, point) in points.enumerated() {
            path.addQuadCurve(to: midpoint(point, points[(index + 1) % points.count]), control: point)
        }
        path.closeSubpath()
        return path
    }
}
