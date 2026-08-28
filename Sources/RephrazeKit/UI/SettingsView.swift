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
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Behind every section, including the ones that are a plain
                // ScrollView rather than a Form.
                .background(SettingsPalette.content)
        }
        .navigationTitle(model.selectedSection.title)
        .frame(minWidth: 860, minHeight: 560)
        // Fixed cream, so the contents must be dark-on-light whatever the
        // system appearance is set to -- the same bargain the result panel
        // makes, and for the same reason.
        .environment(\.colorScheme, .light)
        // The mark's indigo, so selection in here matches the panel and the
        // icon rather than whatever accent the system is set to.
        .tint(PanelPalette.accent)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SettingsSection.allCases, selection: $model.selectedSection) { section in
            NavigationLink(value: section) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(section.title)
                            .font(.system(size: 14))
                        Text(section.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: section.symbol)
                        .font(.system(size: 16))
                        .frame(width: 22)
                }
                .padding(.vertical, 5)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top) {
            // The mark leads the window rather than closing it. At the bottom
            // it read as a footer -- a version stamp you notice on the way out.
            // At the top it is the app introducing itself, which is what a mark
            // is for, and it gives the sidebar a head where the sections start
            // flush against the title bar otherwise.
            HStack(spacing: 11) {
                // Mark and wordmark at roughly the same height, which is what
                // makes a lockup read as one thing rather than an icon with a
                // caption beside it.
                RephrazeMarkView(size: 30)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppInfo.name)
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.3)
                    // Secondary rather than tertiary: tertiary is faint enough
                    // on a sidebar's translucent background that the version
                    // has to be hunted for, which defeats printing it.
                    Text("Version \(AppInfo.version)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        // Applied after the inset so the lockup sits on the same tone as the
        // list rather than on a lighter strip above it.
        .background(SettingsPalette.sidebar)
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
