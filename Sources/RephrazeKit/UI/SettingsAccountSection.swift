import SwiftUI

/// The "Account" section.
///
/// ## There is no account
/// Rephraze has no sign-in, no server and no record of you anywhere. Your key
/// goes straight from this Mac's Keychain to OpenAI, and nothing about you
/// passes through anything of ours on the way. So this section is the honest
/// version of an account page: the one credential the app holds, where it is
/// kept, the address a reply would go to, and how to remove both.
// MARK: - Account

struct AccountTab: View {
    @ObservedObject var model: SettingsModel
    var onDone: () -> Void

    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 11) {
                        Image(systemName: model.hasStoredKey ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.badge.questionmark")
                            .font(.system(size: 27))
                            .foregroundStyle(model.hasStoredKey ? Color.green : Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.hasStoredKey ? "Signed in with your own key" : "No key yet")
                                .font(.system(size: 14, weight: .medium))
                            Text(model.hasStoredKey
                                 ? "Rephraze talks to OpenAI as you. Nothing goes through a server of ours."
                                 : "Rephraze cannot rewrite anything until there is a key below.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }

                Section {
                    SecureField(
                        model.hasStoredKey ? "Saved — type a new key to replace it" : "sk-…",
                        text: $model.apiKeyInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($keyFieldFocused)
                    .onSubmit(save)

                    if model.hasStoredKey {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("Key stored in your Keychain")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove", role: .destructive, action: model.removeKey)
                                .buttonStyle(.link)
                        }
                        .font(.callout)
                    }
                } header: {
                    Text("OpenAI API key")
                } footer: {
                    Text("""
                        Kept in the macOS Keychain — never written to a file, a log, or \
                        the app itself. Removing it is the whole of signing out: there is \
                        no session anywhere else to end.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    TextField("you@example.com", text: $model.ticketReplyTo)
                        .textFieldStyle(.roundedBorder)

                    if model.replyAddressLooksWrong {
                        Label("That does not look like an address a reply could reach.", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Where a reply would go")
                } footer: {
                    Text("""
                        Used only if you send a report from Help, and kept on this Mac so \
                        you do not type it twice. It is never attached to a rewrite, never \
                        sent to OpenAI, and never part of a usage report.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("This install") {
                        Text(model.installID)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("Identity")
                } footer: {
                    Text("""
                        A random number made on this Mac — not your name, your email or \
                        anything about the hardware. It is the closest thing to an account \
                        identifier that exists, it is used only if you turn usage reports \
                        on, and Data and Privacy has the button that throws it away.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .settingsContentBackground()

            Divider()

            HStack {
                SettingsStatusLine(status: model.status, hasStoredKey: model.hasStoredKey)
                Spacer()
                Button("Done", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onAppear { keyFieldFocused = !model.hasStoredKey }
    }

    private func save() {
        let hadNoKeyBefore = !model.hasStoredKey
        // The reply address is typed here now, so it is saved here too rather
        // than only when a support report goes out.
        Settings.replyAddress = model.ticketReplyTo.trimmingCharacters(in: .whitespacesAndNewlines)
        model.save()

        if case .error = model.status { return }

        // First key saved: show History so the window has somewhere to be,
        // rather than vanishing and leaving you wondering what happened.
        if hadNoKeyBefore && model.hasStoredKey {
            model.selectedSection = .history
            return
        }

        onDone()
    }
}
