import SwiftUI

/// The "General" section: the shortcut that summons a rewrite, the model behind
/// it, and how fast it is fetched.
///
/// The key moved to Account and the allowance moved to Plans and Billing. What
/// is left is the answer to one question -- how does this app behave when I use
/// it -- and the shortcut leads because it is the only part of Rephraze most
/// people ever touch.
// MARK: - General

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Tap twice", selection: Binding(
                        get: { model.triggerKey },
                        set: model.setTriggerKey
                    )) {
                        ForEach(TriggerKey.allCases, id: \.self) { key in
                            // Symbol and name together. The symbol is what is
                            // printed on the keycap; the name is what someone
                            // who has never looked at the keycap can read.
                            Text("\(key.displayName)  \(key.label)").tag(key)
                        }
                    }

                    if let caveat = model.triggerKey.caveat {
                        Label(caveat, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Shortcut")
                } footer: {
                    Text("""
                        Tap \(model.triggerDescription) with nothing else held down and \
                        Rephraze reads whatever text box you are in. Holding the key as \
                        part of a normal shortcut never triggers it — it has to be two \
                        taps of that key on its own.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Picker("How quickly", selection: Binding(
                        get: { model.doubleTapWindow },
                        set: model.setDoubleTapWindow
                    )) {
                        ForEach(SettingsModel.doubleTapSpeeds, id: \.seconds) { speed in
                            Text(speed.name).tag(speed.seconds)
                        }
                        // A window set by an older build, or by hand in the
                        // defaults, still has to be selectable — otherwise the
                        // picker shows nothing and the first click silently
                        // changes a setting the user never touched.
                        if !SettingsModel.doubleTapSpeeds.contains(where: { $0.seconds == model.doubleTapWindow }) {
                            Text("Custom").tag(model.doubleTapWindow)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let note = SettingsModel.doubleTapSpeeds
                        .first(where: { $0.seconds == model.doubleTapWindow })?.note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Double-tap speed")
                } footer: {
                    Text("""
                        How long the second tap has got to arrive. Change it if the \
                        shortcut keeps firing when you did not mean it, or keeps missing \
                        when you did — the right gap is a property of your hand, not of \
                        the app.
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
                SettingsStatusLine(status: model.status, hasStoredKey: model.hasStoredKey)
                Spacer()
                Button("Done", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    private func save() {
        model.save()
        if case .error = model.status { return }
        onDone()
    }
}

/// The saved / failed / no-key line that sits in the footer of every section
/// with a Done button.
///
/// One view rather than a copy per section: three sections press the same
/// `save()` and have to report the same three outcomes, and three copies of
/// that would be three places for the wording to drift apart.
struct SettingsStatusLine: View {
    let status: SettingsModel.Status
    let hasStoredKey: Bool

    var body: some View {
        switch status {
        case .idle:
            if !hasStoredKey {
                Label("Add a key in Account to start rephrasing", systemImage: "exclamationmark.triangle.fill")
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
}
