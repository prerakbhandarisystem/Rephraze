import SwiftUI

/// The "Translation" section.
///
/// Most of what is planned here is not built, and the section says so rather
/// than hiding until it is. What *does* work — ⌥T on the panel, composing
/// directly in one of ten languages — is set up at the bottom, so the tab is
/// useful today instead of being a placeholder you learn to skip.
// MARK: - Translation

struct TranslationTab: View {
    @ObservedObject var model: SettingsModel

    /// What is actually coming. Written as claims someone has to keep rather
    /// than as a mood board: each one is a thing you will be able to do.
    private static let planned = [
        ("text.append", "Translate as you type", "Hold the shortcut and keep writing — each sentence lands in the other language as you finish it."),
        ("doc.text", "Whole documents", "Point it at a file rather than a text box, and get the same voice back in another language."),
        ("character.book.closed", "Your terms, kept", "A glossary of names, products and phrases that must survive translation untouched."),
        ("globe.badge.chevron.backward", "More languages", "Beyond the ten below, including the ones with no good machine translation today."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Self.planned, id: \.0) { item in
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: item.0)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tint)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.1)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(item.2)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    HStack(spacing: 7) {
                        Text("Coming soon")
                        // A pill rather than more prose. The heading has to be
                        // unmissable at a glance, because the whole point of
                        // this card is that none of it works yet.
                        Text("NOT BUILT YET")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(.tint)
                            )
                    }
                } footer: {
                    Text("""
                        None of the four above is written yet, and nothing on this card \
                        will do anything if you click it. It is here so you know what \
                        Translation is going to be rather than finding out later.
                        """)
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
                    Text("Working today")
                } footer: {
                    Text("""
                        Press ⌥T on the rewrite panel. Set a language here and it goes \
                        straight there; press ⌥T again to pick a different one. Either \
                        way the message is composed directly in that language, never \
                        translated out of an English rewrite.
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
                Button("Done") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }
}
