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

            VoiceTab(model: model)
                .tabItem { Label("Your voice", systemImage: "person.wave.2") }
                .tag(SettingsTab.voice)

            HistoryTab(model: model)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

// MARK: - Your voice

/// A short wizard that works out how someone writes, then hands them the
/// description it produced.
///
/// The questions are adaptive: answering "formal" means it never asks about
/// emoji, because that question is already answered. Most people finish in six
/// or seven, and the result is editable prose rather than a locked-in profile.
private struct VoiceTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if let question = model.currentQuestion {
                        questionCard(question)
                    } else {
                        resultCard
                    }
                }
                .padding(22)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                if model.canGoBack {
                    Button("Back", action: model.goBack)
                }
                Spacer()
                if model.wizardIsComplete || model.hasVoice {
                    Button("Start over", action: model.restartWizard)
                    Button("Save voice", action: model.saveVoice)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Teach it how you sound")
                .font(.title3.weight(.semibold))
            Text("""
                Answer a few questions and Rephraze will rewrite in your voice \
                instead of offering four generic tones. You can edit the result \
                afterwards, or write it yourself.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func questionCard(_ question: VoiceQuestion) -> some View {
        let progress = model.wizardProgress

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Question \(progress.asked + 1) of about \(max(progress.total, progress.asked + 1))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(question.prompt)
                    .font(.headline)
                if !question.help.isEmpty {
                    Text(question.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 8) {
                ForEach(question.options) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            model.answer(question.id, with: option.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("This is how Rephraze will write for you")
                    .font(.headline)
            }

            Text("Edit it freely — it is just instructions, in plain English.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $model.voiceText)
                .font(.system(size: 12.5))
                .frame(minHeight: 150)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

            if !model.voiceAnswers.isEmpty {
                Button("Rebuild from my answers", action: model.regenerateVoiceText)
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Divider().padding(.vertical, 2)

            Toggle("Use my voice instead of the four tones", isOn: $model.voiceEnabled)
                .font(.callout)

            Text("""
                While this is on, ⌥⌥ returns one rewrite in your voice. Turn it \
                off to go back to the four options without losing what you wrote.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
