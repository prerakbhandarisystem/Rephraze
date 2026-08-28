import SwiftUI

/// The "Support" section: write a report, see exactly what goes with it, send
/// it.
///
/// The screen is arranged around the one thing a support form in this app has
/// to get right — that the sender can see the whole message before it moves.
/// So the diagnostics are shown in full rather than described, and the button
/// says what actually happens: one press and the report is sent, with the
/// screen waiting on the server rather than claiming anything early.
// MARK: - Support

struct SupportTab: View {
    @ObservedObject var model: SettingsModel

    @FocusState private var summaryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("", selection: $model.ticketKind) {
                        ForEach(TicketKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    TextField("One line — what is the matter?", text: $model.ticketSummary)
                        .textFieldStyle(.roundedBorder)
                        .focused($summaryFocused)

                    TextField("Your email, if you would like an answer", text: $model.ticketReplyTo)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                } header: {
                    Text("Report")
                } footer: {
                    Group {
                        if model.replyAddressLooksWrong {
                            Label(
                                "That address is missing something — a reply would bounce.",
                                systemImage: "exclamationmark.circle"
                            )
                            .foregroundStyle(.orange)
                        } else {
                            Text("Only ever used to write back. Leave it empty to report anonymously.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }

                Section {
                    detailEditor
                } header: {
                    Text("Details")
                } footer: {
                    Text("Optional, but a report with steps in it gets fixed sooner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Attach these details", isOn: $model.ticketIncludesDiagnostics)

                    if model.ticketIncludesDiagnostics {
                        diagnosticsList
                    }
                } header: {
                    Text("What gets attached")
                } footer: {
                    Text("""
                        Versions, settings and counts — the whole of it, shown above. \
                        Never the text you typed, never anything from History, never \
                        your API key.
                        """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .settingsContentBackground()

            Divider()

            HStack(spacing: 10) {
                statusView
                Spacer()
                Button("Copy Instead", action: model.copyTicket)
                    .disabled(!model.canSendTicket)
                Button(model.sendsTicketsDirectly ? "Send Report" : "Open in Mail",
                       action: model.sendTicket)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSendTicket)
            }
            .padding(12)
        }
        .onAppear {
            model.refreshDiagnostics()
            summaryFocused = model.ticketSummary.isEmpty
        }
    }

    // MARK: - Pieces

    /// Same treatment as the writing-style editor, with a placeholder laid over
    /// it — `TextEditor` has no prompt of its own.
    private var detailEditor: some View {
        TextEditor(text: $model.ticketDetail)
            .font(.system(size: 12.5))
            .frame(minHeight: 130)
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                if model.ticketDetail.isEmpty {
                    Text(model.ticketKind.prompt)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 15)
                        .allowsHitTesting(false)
                }
            }
    }

    private var diagnosticsList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.diagnostics.fields) { field in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(field.label)
                        .foregroundStyle(.secondary)
                        .frame(width: 128, alignment: .leading)
                    Text(field.value)
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.4))
        )
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.ticketStatus {
        case .idle:
            Text(
                model.sendsTicketsDirectly
                    ? "Goes straight to \(AppInfo.supportEmail)"
                    : "Opens in your mail app, addressed to \(AppInfo.supportEmail)"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        case .sending:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Sending…")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        case .sent:
            HStack(spacing: 8) {
                // "Sent", not "submitted": the server waited for the mail to go
                // before it answered, so this says the thing that happened.
                Label("Sent — it is in the inbox", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("New Report", action: model.newTicket)
                    .buttonStyle(.link)
            }
            .font(.callout)
        case let .failed(reason):
            Label(
                "\(reason) It is on your clipboard, so nothing is lost.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .font(.callout)
        case .handedOff:
            HStack(spacing: 8) {
                Label("Waiting in your mail app — press send there", systemImage: "envelope.fill")
                    .foregroundStyle(.green)
                Button("New Report", action: model.newTicket)
                    .buttonStyle(.link)
            }
            .font(.callout)
        case .copied:
            Label("Copied — paste it into an email", systemImage: "doc.on.clipboard.fill")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
