import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum AppTheme: String, CaseIterable, Identifiable {
    case monochrome, sunset, pink

    static let storageKey = "appearanceTheme"
    static let defaultTheme = Self.pink
    var id: Self { self }

    var name: String {
        switch self {
        case .monochrome: "Noir"
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
    #if os(macOS)
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
    #elseif os(iOS)
    private static let artwork = Bundle.main.url(forResource: "Wordmark", withExtension: "png")
        .flatMap { UIImage(contentsOfFile: $0.path) }
    #endif

    let width: CGFloat

    var body: some View {
        Group {
            #if os(macOS)
            if let artwork = Self.artwork {
                Image(nsImage: artwork).renderingMode(.template)
                    .resizable().scaledToFit().accessibilityLabel("Archaive")
            } else {
                Text("Archaive").font(.system(size: width / 5, weight: .black, design: .rounded))
            }
            #elseif os(iOS)
            if let artwork = Self.artwork {
                Image(uiImage: artwork).renderingMode(.template)
                    .resizable().scaledToFit().accessibilityLabel("Archaive")
            } else {
                Text("Archaive").font(.system(.title3, design: .rounded, weight: .black))
            }
            #endif
        }
        .frame(width: width)
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
