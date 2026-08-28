import SwiftUI

/// The "Team" section.
///
/// ## A team here is a file, not a server
/// There are no accounts to invite anyone to. What a team actually wants from
/// one, though, is real and buildable: everybody's rewrites sounding like the
/// same house. So a voice is exported to a file, sent over whatever the team
/// already uses, and imported by everyone else — reviewable before it is
/// trusted, and with nobody handing their writing to a third party to share how
/// they write.
// MARK: - Team

struct TeamTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.tint)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("No sign-in, no seats, no server")
                            .font(.system(size: 14, weight: .medium))
                        Text("""
                            Rephraze keeps nothing about you anywhere we could look, so \
                            there is nobody to invite. A shared voice travels as a file \
                            instead: export yours, send it however you already send \
                            things, and everyone who imports it writes in the same voice.
                            """)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
            }

            Section {
                TextField("Name this voice", text: $model.profileName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Export…", action: model.exportStyleProfile)
                        .disabled(!model.hasStyle)
                }

                if !model.hasStyle {
                    Label(
                        "Answer the questions in Writing style first — there is nothing to export yet.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Share your voice")
            } footer: {
                Text("""
                    The file holds the description your rewrites are written against and \
                    the answers behind it — so whoever receives it can revise the voice, \
                    not just inherit it. It carries no API key, nothing you have \
                    rephrased, and no identifier that says it came from you.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Import…", action: model.importStyleProfile)
                }

                statusRow
            } header: {
                Text("Adopt someone else's")
            } footer: {
                Text("""
                    Importing replaces the writing style on this Mac and switches it on. \
                    Yours is overwritten, so export it first if you want to keep it — the \
                    file is plain text you can read before you trust it.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsContentBackground()
        .onAppear { model.refresh() }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.profileStatus {
        case .idle:
            EmptyView()
        case let .exported(filename):
            Label("Saved as \(filename)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case let .imported(name):
            Label("Now writing in “\(name)”", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
