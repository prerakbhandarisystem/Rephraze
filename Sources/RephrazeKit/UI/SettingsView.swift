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

    /// Whether the sidebar is showing. Driven by the toolbar button, and kept
    /// here rather than read back from AppKit so the button and the columns
    /// can never disagree about which state they are in.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(model: SettingsModel, onDone: @escaping () -> Void) {
        self.model = model
        self.onDone = onDone
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 236, ideal: 262, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Behind every section, including the ones that are a plain
                // ScrollView rather than a Form.
                .background(SettingsPalette.content)
        }
        .navigationTitle(model.selectedSection.title)
        .toolbar {
            // Leading, so it lands just after the traffic lights -- the place
            // macOS puts this control in every window that has one, which is
            // why it needs no label to be understood.
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help(columnVisibility == .detailOnly ? "Show sections" : "Hide sections")
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        // Fixed cream, so the contents must be dark-on-light whatever the
        // system appearance is set to -- the same bargain the result panel
        // makes, and for the same reason.
        .environment(\.colorScheme, .light)
        // The tint follows the open section, so a switch, a chosen row and the
        // sidebar highlight are all the colour of the chip you clicked to get
        // here. It carries the colour past the icons into the window itself,
        // which is what stops the chips reading as decoration bolted onto a
        // grey app.
        .tint(model.selectedSection.tint)
        .animation(.easeOut(duration: 0.18), value: model.selectedSection)
    }

    /// Collapse the sidebar, or bring it back.
    ///
    /// Animated on purpose: the columns sliding is what tells you the sidebar
    /// was hidden rather than lost, so the way back is obvious.
    private func toggleSidebar() {
        withAnimation(.easeOut(duration: 0.2)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $model.selectedSection) {
            // Two headed groups rather than one flat list. Nine rows in a
            // column is a list you scan top to bottom every time; nine rows
            // under "Settings" and "Account" is a list where half of it can be
            // ignored the moment you know which half you are in.
            ForEach(SettingsSection.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        NavigationLink(value: section) {
                            row(section)
                        }
                    }
                }
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
            // Small, because the toolbar's own height is already above this.
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .safeAreaInset(edge: .bottom) { utilityStrip }
        // Applied after the insets so the lockup and the strip sit on the same
        // tone as the list rather than on lighter bands above and below it.
        .background(SettingsPalette.sidebar)
    }

    /// One sidebar row: coloured chip, title, and the line that says what the
    /// section is for.
    ///
    /// An explicit HStack rather than a Label.
    ///
    /// `Label` decides for itself how to line an icon up against its title, and
    /// its answer is wrong for a two-line title: it works from the first line,
    /// so a chip shorter than the block sits high against it. Centring the chip
    /// on the whole block is the only thing that looks straight, and that has
    /// to be stated rather than hoped for.
    private func row(_ section: SettingsSection) -> some View {
        HStack(spacing: 10) {
            // A white glyph on a coloured chip, the way macOS's own Settings
            // does it. The colour is the thing you actually navigate by once
            // you know the window -- you reach for the orange one, and read the
            // label only to confirm.
            //
            // Sized to the height of the two lines beside it. A chip materially
            // shorter than its own label reads as a bullet point; one that
            // matches reads as the row's subject.
            Image(systemName: section.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(section.tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 15.5))
                Text(section.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Settings and help

    /// The section that lives in the corner instead of in the list.
    ///
    /// Drawn flatter and smaller than a list row on purpose. These are the
    /// places you leave and come back from, not the sections the window is
    /// about, and giving them the full chip-and-summary treatment would say
    /// the opposite.
    private var utilityStrip: some View {
        VStack(spacing: 0) {
            Divider().overlay(SettingsPalette.hairline)

            HStack(spacing: 6) {
                ForEach(SettingsSection.utility) { section in
                    utilityButton(section)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
    }

    private func utilityButton(_ section: SettingsSection) -> some View {
        let isActive = model.selectedSection == section

        return Button {
            model.selectedSection = section
        } label: {
            HStack(spacing: 7) {
                // The section's own colour, not the window tint -- the window
                // tint is whatever section is open, which would make both of
                // these change colour every time you clicked something else.
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : section.tint)
                Text(section.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? AnyShapeStyle(section.tint) : AnyShapeStyle(.clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch model.selectedSection {
        case .general:     GeneralTab(model: model, onDone: onDone)
        case .system:      SystemTab(model: model)
        case .translation: TranslationTab(model: model)
        case .style:       StyleTab(model: model)
        case .history:     HistoryTab(model: model)
        case .account:     AccountTab(model: model, onDone: onDone)
        case .team:        TeamTab(model: model)
        case .billing:     BillingTab(model: model)
        case .usage:       UsageTab(model: model)
        case .help:        SupportTab(model: model)
        }
    }
}
