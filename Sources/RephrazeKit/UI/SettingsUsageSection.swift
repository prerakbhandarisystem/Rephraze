import SwiftUI

/// The "Usage" section: the consent screen for anonymous usage reporting.
///
/// It is written as a disclosure rather than a switch with a label. The rest of
/// this app promises that what you type stays on the Mac, so the one feature
/// that sends anything at all has to show its whole hand — every event it can
/// send, what identifies the install, and how to become a different install.
// MARK: - Usage

struct UsageTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(
                        "Share anonymous usage reports",
                        isOn: Binding(
                            get: { model.usageReportingEnabled },
                            set: model.setUsageReporting
                        )
                    )
                    .disabled(!model.usageEndpointConfigured)

                    if !model.usageEndpointConfigured {
                        Label(
                            "This build has no reporting address, so nothing is collected.",
                            systemImage: "info.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Usage reporting")
                } footer: {
                    Text("""
                        Off unless you turn it on. It helps show which parts of Rephraze \
                        get used and which quietly do not — nothing more.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(SettingsModel.usageEventDescriptions, id: \.0) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(event.0)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .frame(width: 84, alignment: .leading)
                                Text(event.1)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Everything it can send")
                } footer: {
                    Text("""
                        That is the complete list. Never the text you rephrase, never a \
                        rewrite, never which app you were in, never your API key. There \
                        is no event that carries free text — the app has no way to send one.
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

                    LabeledContent("Waiting to send") {
                        Text("\(model.queuedUsageEvents)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Spacer()
                        Button("Reset Identifier", action: model.resetInstallID)
                    }
                } header: {
                    Text("Identity")
                } footer: {
                    Text("""
                        A random number made on this Mac — not your name, your email, your \
                        login or anything about the hardware. Resetting it discards \
                        anything still queued and makes this a brand new install, with no \
                        way to connect it to what came before.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text(
                    model.usageEndpointConfigured
                        ? "Sends to \(model.usageEndpointDescription)"
                        : "No reporting address in this build"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                Spacer()
            }
            .padding(12)
        }
        .onAppear { model.refresh() }
    }
}
