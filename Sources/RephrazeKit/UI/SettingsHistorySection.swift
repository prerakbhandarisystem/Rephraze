import SwiftUI

/// The "History" section: what the app has rewritten, and the controls for
/// clearing it.
// MARK: - History

struct HistoryTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            if model.records.isEmpty {
                emptyState
            } else {
                searchField

                List(model.filteredRecords) { record in
                    HistoryRow(record: record)
                        .listRowSeparator(.visible)
                }
                .listStyle(.inset)
                .settingsContentBackground()
            }

            Divider()

            // The switch lives here rather than in General, beside the list it
            // governs and the button that empties it -- the three history
            // controls in one place instead of two.
            HStack(spacing: 14) {
                Toggle(
                    "Keep a record",
                    isOn: Binding(
                        get: { model.historyEnabled },
                        set: model.setHistoryEnabled
                    )
                )
                .toggleStyle(.checkbox)
                .font(.callout)

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

    /// A field in the view, not in the toolbar.
    ///
    /// `.searchable(placement: .toolbar)` put an NSSearchToolbarItem in the
    /// window toolbar, which carries a wide minimum of its own. Because it was
    /// attached to this section alone, it appeared the moment History was
    /// selected -- pushing the window's minimum width up and making the whole
    /// window jump wider on a tab change. A field that lives in the section's
    /// own layout searches the same way and leaves the toolbar, and therefore
    /// the window, exactly as it was.
    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("Search rephrases", text: $model.searchTerm)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))

            if !model.searchTerm.isEmpty {
                Button {
                    model.searchTerm = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary.opacity(0.4))
        )
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
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

struct HistoryRow: View {
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

            // 14, deliberately the largest text in the window. Every other
            // section is labels and controls, which want to be small and get
            // out of the way. This one is the only place you sit and *read* --
            // whole sentences, compared against each other -- so it is sized
            // for reading rather than for matching the chrome around it.
            Text(record.original)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .strikethrough(record.accepted, color: .secondary.opacity(0.5))
                .lineLimit(2)

            Text(record.rewritten)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .padding(.vertical, 5)
    }
}
