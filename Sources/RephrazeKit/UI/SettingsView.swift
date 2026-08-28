import SwiftUI

/// The settings window: a sidebar of sections on the left, the chosen one on
/// the right.
///
/// A sidebar rather than a row of tabs. Tabs across the top work for two or
/// three items of equal weight and stop working the moment there are more or
/// they differ in depth -- which is already true here, where "Writing style" is
/// a multi-step wizard sitting beside a short list of switches. The sidebar
/// also has room for the one-line summaries, so the window says what it
/// contains without being clicked through.
public struct SettingsView: View {

    @ObservedObject var model: SettingsModel
    var onDone: () -> Void

    public init(model: SettingsModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 208, ideal: 224, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(model.selectedSection.title)
        .frame(minWidth: 860, minHeight: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $model.selectedSection) { section in
            NavigationLink(value: section) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.title)
                            .font(.system(size: 13))
                        Text(section.summary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 13))
                        .frame(width: 18)
                }
                .padding(.vertical, 3)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            // The app's own identity, and the one control that is not part of
            // any single section.
            HStack(spacing: 8) {
                RephrazeMarkView(size: 15)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rephraze")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Version \(AppInfo.version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .general: GeneralTab(model: model, onDone: onDone)
        case .style:   StyleTab(model: model)
        case .history: HistoryTab(model: model)
        case .usage:   UsageTab(model: model)
        case .support: SupportTab(model: model)
        }
    }
}
