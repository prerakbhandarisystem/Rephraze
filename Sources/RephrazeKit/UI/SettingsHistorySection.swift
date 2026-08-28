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
