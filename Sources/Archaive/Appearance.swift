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

// Slightly different radii on each lobe keep the advancing edge uneven.
struct InkSpread: Shape {
    var progress: CGFloat
    let origin: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let reach = hypot(max(origin.x, rect.width - origin.x),
                          max(origin.y, rect.height - origin.y)) * 1.2
        let radius = reach * max(0, progress)
        let lobes: [CGFloat] = [1.05, 0.94, 1.10, 0.96, 1.06, 0.92, 1.07, 0.98, 1.12, 0.95, 1.03]
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

/// Four curves morph the crescent into the sun's outline around the sleep control.
struct ModeOrbit: Shape {
    var progress: CGFloat

    init(awake: Bool) { progress = awake ? 1 : 0 }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let moon: [CGPoint] = [
        CGPoint(x: 76, y: 8),
        CGPoint(x: 30, y: -3), CGPoint(x: 11, y: 25), CGPoint(x: 11, y: 50),
        CGPoint(x: 11, y: 75), CGPoint(x: 30, y: 103), CGPoint(x: 76, y: 92),
        CGPoint(x: 50, y: 88), CGPoint(x: 32, y: 71), CGPoint(x: 32, y: 50),
        CGPoint(x: 32, y: 29), CGPoint(x: 50, y: 12), CGPoint(x: 76, y: 8)
    ]

    private static let sun: [CGPoint] = [
        CGPoint(x: 50, y: 12),
        CGPoint(x: 29, y: 12), CGPoint(x: 12, y: 29), CGPoint(x: 12, y: 50),
        CGPoint(x: 12, y: 71), CGPoint(x: 29, y: 88), CGPoint(x: 50, y: 88),
        CGPoint(x: 71, y: 88), CGPoint(x: 88, y: 71), CGPoint(x: 88, y: 50),
        CGPoint(x: 88, y: 29), CGPoint(x: 71, y: 12), CGPoint(x: 50, y: 12)
    ]

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 100
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - 50) * unit, y: rect.midY + (y - 50) * unit)
        }
        let points = zip(Self.moon, Self.sun).map { moon, sun in
            point(moon.x + (sun.x - moon.x) * progress, moon.y + (sun.y - moon.y) * progress)
        }
        var path = Path()
        path.move(to: points[0])
        for index in stride(from: 1, to: points.count, by: 3) {
            path.addCurve(to: points[index + 2], control1: points[index], control2: points[index + 1])
        }
        path.closeSubpath()

        let rayLength = 6 * max(0, (progress - 0.52) / 0.48)
        if rayLength > 0 {
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                path.move(to: point(50 + 43 * cos(angle), 50 + 43 * sin(angle)))
                path.addLine(to: point(50 + (43 + rayLength) * cos(angle), 50 + (43 + rayLength) * sin(angle)))
            }
        }
        return path
    }
}
