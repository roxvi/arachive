import SwiftUI

private enum Example: String, CaseIterable, Identifiable {
    case export = "Finish a long export"
    case lid = "Dim the display at your desk"
    case focus = "Keep one app running"
    case hotspot = "Recover from a Wi-Fi drop"
    case phone = "Follow along on your phone"
    case shortcut = "Switch modes with a shortcut"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .export: "sun.max"
        case .lid: "laptopcomputer"
        case .focus: "scope"
        case .hotspot: "wifi"
        case .phone: "iphone"
        case .shortcut: "keyboard"
        }
    }

    var detail: String {
        switch self {
        case .export: "Keep Awake lets an export or download continue when you close the lid."
        case .lid: "With Keep Awake on, closing the lid can dim supported displays to zero. Opening it restores the previous brightness."
        case .focus: "Choose which apps stay active. Focus pauses other eligible apps until your session ends."
        case .hotspot: "When Wi-Fi drops, Archaive can try the hotspot you configured."
        case .phone: "Share a view-only feed of your Mac to a phone on the same local network."
        case .shortcut: "Use your global keyboard shortcut to switch between normal sleep and Keep Awake."
        }
    }

    var action: String {
        switch self {
        case .export: "Close the lid"
        case .lid: "Close the lid"
        case .focus: "Begin Focus"
        case .hotspot: "Drop Wi-Fi"
        case .phone: "Scan the sample code"
        case .shortcut: "Press shortcut"
        }
    }

    func status(active: Bool) -> String {
        switch self {
        case .export: active ? "Lid closed · Export continues" : "Lid open · Video exporting"
        case .lid: active ? "Display dimmed to 0% · Mac awake" : "Display at 65% · Mac awake"
        case .focus: active ? "Editor running · Browser paused" : "Editor and browser running"
        case .hotspot: active ? "Connected to Demo iPhone" : "Connected to Studio Wi-Fi"
        case .phone: active ? "Screen visible on the phone" : "Waiting for the phone to connect"
        case .shortcut: active ? "Keep Awake is on" : "Normal sleep is on"
        }
    }

    func stageSymbol(active: Bool) -> String {
        guard active else { return symbol }
        return switch self {
        case .export: "arrow.down.circle"
        case .lid: "display"
        case .focus: "checkmark.circle"
        case .hotspot: "personalhotspot"
        case .phone: "iphone.gen3"
        case .shortcut: "sun.max"
        }
    }
}

struct ExamplesPage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = Example.export
    @State private var active = false
    let shortcut: Shortcut

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                scenarios.frame(width: 220)
                stage.frame(minWidth: 300)
            }
            VStack(alignment: .leading, spacing: 16) {
                stage
                scenarios
            }
        }
    }

    private var scenarios: some View {
        VStack(spacing: 3) {
            ForEach(Example.allCases) { example in
                Button {
                    selection = example
                    active = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: example.symbol).frame(width: 22)
                        Text(example.rawValue)
                        Spacer(minLength: 0)
                        if selection == example {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                    }
                    .font(.system(size: 13, weight: selection == example ? .semibold : .regular))
                    .padding(10)
                    .background(selection == example ? theme.wash.opacity(0.48) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == example ? .isSelected : [])
            }
        }
        .padding(10)
        .modifier(FogPanel())
    }

    private var stage: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(selection.rawValue)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            Text(selection.detail)
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                Image(systemName: selection == .phone && !active ? "qrcode" : selection.stageSymbol(active: active))
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
                if selection == .shortcut {
                    Text(shortcut.label).font(.system(.callout, design: .monospaced))
                }
                Text(selection.status(active: active))
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .multilineTextAlignment(.center)
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 114)
            .background(theme.wash.opacity(active ? 0.55 : 0.22), in: RoundedRectangle(cornerRadius: 16))
            Button(active ? "Reset example" : selection.action) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { active.toggle() }
            }
            .buttonStyle(InkButton())
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FogPanel())
    }
}
