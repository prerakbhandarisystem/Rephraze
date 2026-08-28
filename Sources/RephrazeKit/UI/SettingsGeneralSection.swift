import SwiftUI

/// The "General" section: API key, model, speed and history switches.
// MARK: - General

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    var onDone: () -> Void

    @FocusState private var keyFieldFocused: Bool

    /// What is left of the allowance, and how much of it has gone.
    ///
    /// Reads `UsageQuota` directly rather than going through `SettingsModel`.
    /// It is a value type over UserDefaults, and the count only ever moves
    /// while the panel is in use -- which is to say while this window is not
    /// the one being looked at.
    private var allowanceRow: some View {
        let quota = UsageQuota()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(quota.isExhausted
                     ? "All \(UsageQuota.allowance) used"
                     : "\(quota.remaining) of \(UsageQuota.allowance) left")
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Text("\(quota.used) used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(
                value: Double(min(quota.used, UsageQuota.allowance)),
                total: Double(UsageQuota.allowance)
            )
            .tint(quota.isRunningLow ? .orange : .accentColor)
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
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
                    Text("Kept in the macOS Keychain — never written to a file, a log, or the app itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    allowanceRow
                } header: {
                    Text("Rewrites")
                } footer: {
                    Text("""
                        Counted when a rewrite goes into your text — dismissing \
                        one, or reading all four and taking none, costs nothing. \
                        Nothing stops working when the allowance runs out.
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Model", selection: $model.model) {
                        ForEach(SettingsModel.suggestedModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        if !SettingsModel.suggestedModels.contains(model.model) {
                            Text(model.model).tag(model.model)
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("A small, fast model keeps rewrites under a second.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Write in", selection: $model.defaultLanguage) {
                        Text("Ask every time").tag(TargetLanguage?.none)
                        Divider()
                        ForEach(TargetLanguage.allCases) { language in
                            Text("\(language.title) — \(language.endonym)")
                                .tag(TargetLanguage?.some(language))
                        }
                    }
                } header: {
                    Text("Translation")
                } footer: {
                    Text("""
                        Press ⌥T on the rewrite panel. Set a language here and it goes \
                        straight there; press ⌥T again to pick a different one. Either way \
                        the message is composed directly in that language, never translated \
                        out of an English rewrite.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Write the four versions at the same time", isOn: $model.parallelVariants)
                } header: {
                    Text("Speed")
                } footer: {
                    Text("""
                        Four requests at once instead of one combined request. The first \
                        version appears about three times sooner, for roughly 20-30% more \
                        tokens. Turn it off to spend less.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }
            .formStyle(.grouped)
            .settingsContentBackground()

            Divider()

            HStack {
                statusView
                Spacer()
                Button("Done", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onAppear { keyFieldFocused = !model.hasStoredKey }
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            if !model.hasStoredKey {
                Label("Add a key to start rephrasing", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case let .error(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
        }
    }

    private func save() {
        let hadNoKeyBefore = !model.hasStoredKey
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
