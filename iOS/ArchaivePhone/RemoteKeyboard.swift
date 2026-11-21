import SwiftUI

struct RemoteKeyboard: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var text = ""
    @FocusState private var focused: Bool
    let send: (PhoneControl.Command) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Click a field on your Mac, then type here and tap Send.")
                        .foregroundStyle(theme.muted)
                    TextField("Text to send", text: $text,
                              prompt: Text("Text to send").foregroundStyle(theme.muted), axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Text to send to your Mac")

                    Button(action: sendText) {
                        Label("Send Text", systemImage: "arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PhoneInkButton())
                    .disabled(text.isEmpty || overLimit)
                    if overLimit {
                        Text("Shorten your text before sending it.").font(.footnote).foregroundStyle(theme.accent)
                    }

                    Label("Mac keys", systemImage: "keyboard")
                        .font(.system(.headline, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(PhoneControl.Key.allCases, id: \.self) { key in
                            Button {
                                send(.key(key))
                            } label: {
                                Text(label(for: key)).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PhoneInkButton(prominent: false))
                            .accessibilityLabel(accessibilityLabel(for: key))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 550)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Mac keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .background(theme.paper)
            .foregroundStyle(theme.ink)
            .onAppear { focused = true }
        }
    }

    private var overLimit: Bool { text.utf16.count > PhoneControl.maximumTextLength }

    private func sendText() {
        guard !text.isEmpty, !overLimit else { return }
        send(.type(text))
        text = ""
    }

    private func label(for key: PhoneControl.Key) -> String {
        switch key {
        case .escape: "Esc"
        case .tab: "Tab"
        case .delete: "Delete"
        case .enter: "Return"
        case .left: "←"
        case .right: "→"
        case .up: "↑"
        case .down: "↓"
        case .undo: "Undo"
        case .copy: "Copy"
        case .paste: "Paste"
        case .selectAll: "Select All"
        }
    }

    private func accessibilityLabel(for key: PhoneControl.Key) -> String {
        switch key {
        case .left: "Left arrow"
        case .right: "Right arrow"
        case .up: "Up arrow"
        case .down: "Down arrow"
        case .escape: "Escape"
        default: label(for: key)
        }
    }
}
