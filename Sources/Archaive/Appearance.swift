import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case monochrome, sunset, pink

    static let storageKey = "appearanceTheme"
    static let defaultTheme = Self.pink
    var id: Self { self }

    var name: String {
        switch self {
        case .monochrome: "Black & White"
        case .sunset: "Sunset"
        case .pink: "P!nk"
        }
    }

    var paper: Color {
        switch self {
        case .monochrome: Color(hex: 0xF5F5F4)
        case .sunset: Color(hex: 0xFFF4E7)
        case .pink: Color(hex: 0xFFF4FD)
        }
    }

    var wash: Color {
        switch self {
        case .monochrome: Color(hex: 0xD9D9D6)
        case .sunset: Color(hex: 0xFFC395)
        case .pink: Color(hex: 0xF9C1EE)
        }
    }

    var ink: Color {
        switch self {
        case .monochrome: Color(hex: 0x1A1A19)
        case .sunset: Color(hex: 0x51291F)
        case .pink: Color(hex: 0x421D38)
        }
    }

    var accent: Color {
        switch self {
        case .monochrome: ink
        case .sunset: Color(hex: 0x963C28)
        case .pink: Color(hex: 0x8F315F)
        }
    }

    var muted: Color { ink.opacity(0.76) }
    var line: Color { ink.opacity(0.15) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.defaultTheme
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

struct Wordmark: View {
    private static let artwork: NSImage? = {
        if let url = Bundle.main.url(forResource: "Wordmark", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "Wordmark", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        #endif
        return nil
    }()

    let width: CGFloat

    var body: some View {
        Group {
            if let artwork = Self.artwork {
                Image(nsImage: artwork).renderingMode(.template)
                    .resizable().scaledToFit().accessibilityLabel("Archaive")
            } else {
                Text("Archaive").font(.system(size: width / 5, weight: .black, design: .rounded))
            }
        }
        .frame(width: width)
    }
}

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

struct ThemeSwatch: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        ZStack {
            Circle().fill(theme.paper)
            Circle().trim(from: 0, to: 0.5).fill(theme.accent)
                .rotationEffect(.degrees(-35))
            Circle().strokeBorder(theme.accent, lineWidth: 1)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, theme.accent)
                    .font(.system(size: 13, weight: .semibold))
                    .background(.white, in: Circle())
            }
        }
        .accessibilityHidden(true)
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
