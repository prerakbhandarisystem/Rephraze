import SwiftUI

/// The settings window. Two tabs: what the app needs to run, and what it has done.
public struct SettingsView: View {

    @ObservedObject var model: SettingsModel
    var onDone: () -> Void

    public init(model: SettingsModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
    }

    public var body: some View {
        TabView(selection: $model.selectedTab) {
            GeneralTab(model: model, onDone: onDone)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            HistoryTab(model: model)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    var onDone: () -> Void

    @FocusState private var keyFieldFocused: Bool

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
                    Toggle(
                        "Keep a record of every rephrase",
                        isOn: Binding(
                            get: { model.historyEnabled },
                            set: model.setHistoryEnabled
                        )
                    )
                } header: {
                    Text("History")
                } footer: {
                    Text("""
                        Stays on this Mac, readable only by you. Bear in mind this file \
                        records text you typed in other apps.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

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
            model.selectedTab = .history
            return
        }

        onDone()
    }
}

// MARK: - History

private struct HistoryTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            if model.records.isEmpty {
                emptyState
            } else {
                List(model.filteredRecords) { record in
                    HistoryRow(record: record)
                        .listRowSeparator(.visible)
                }
                .listStyle(.inset)
                .searchable(text: $model.searchTerm, placement: .toolbar, prompt: "Search rephrases")
            }

            Divider()

            HStack {
                Text("\(model.records.count) recorded · newest first")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All", role: .destructive, action: model.clearHistory)
                    .disabled(model.records.isEmpty)
            }
            .padding(12)
        }
        .onAppear { model.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("No rephrases yet")
                .font(.headline)
            Text("Double-tap ⌥ in any text box to make one.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let record: RephraseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(record.appName)
                    .font(.caption.weight(.semibold))
                Text(record.date, format: .dateTime.hour().minute().day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if record.accepted {
                    Label("Used", systemImage: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
            }

            Text(record.original)
                .font(.callout)
                .foregroundStyle(.secondary)
                .strikethrough(record.accepted, color: .secondary.opacity(0.5))
                .lineLimit(2)

            Text(record.rewritten)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(.vertical, 5)
    }
}
