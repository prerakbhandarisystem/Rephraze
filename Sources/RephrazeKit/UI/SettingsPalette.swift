import SwiftUI

/// The settings window's two tones.
///
/// Warm cream for the navigation, plain white for whatever section is open.
/// The separation is the point -- the sidebar is a place you pass through and
/// the content is where you stop, and a single flat background says neither.
/// White rather than a lighter cream: against a warm sidebar it reads as a
/// page laid on a desk, and it is the tone every section's text was chosen to
/// sit on.
///
/// ## Why these are fixed values and not system colours
/// The same reason `PanelPalette` is. A warm cream surface cannot borrow the
/// system's semantic colours, because those invert with the appearance setting
/// and would put light grey text on cream the moment someone switches to dark.
/// So the window fixes its own light palette and forces a light colour scheme
/// over its contents. Every value here has red > green > blue; lose that
/// ordering and the warmth goes with it.
enum SettingsPalette {

    /// The sidebar: the warmer and darker of the two.
    static let sidebar = Color(red: 0.937, green: 0.922, blue: 0.894)

    /// The open section. The one value here that is not warm, and deliberately
    /// so -- it is the page, and the cream around it is the furniture.
    static let content = Color.white

    /// The line between the two columns, and under the footers.
    static let hairline = Color(red: 0.878, green: 0.859, blue: 0.827)

    /// The second line of a sidebar row.
    ///
    /// A fixed tone rather than `.secondary`, for the same reason everything
    /// else here is fixed. `.secondary` is a translucency, and translucent grey
    /// laid over cream comes out weaker than the same grey over white -- which
    /// is exactly where these summaries are, and exactly why they read as faint.
    /// This is 5.8:1 against the sidebar, so it is body text you can actually
    /// read rather than a hint you have to lean in for.
    static let sidebarSecondary = Color(red: 0.373, green: 0.353, blue: 0.318)

    /// The "Settings" and "Account" headings above each group.
    ///
    /// Lighter than the summaries and set in small capitals at the call site.
    /// A heading has to be findable without competing with the rows under it,
    /// and weight plus letterspacing does that job better than darkness does.
    static let sidebarHeading = Color(red: 0.451, green: 0.427, blue: 0.384)
}

extension View {
    /// Put a section on the content tone.
    ///
    /// `Form` and `List` each paint an opaque background of their own, which
    /// would sit on top of anything set behind them -- hiding the tone and
    /// leaving the window flat. Hiding the scroll background first is what
    /// makes the colour underneath visible at all.
    func settingsContentBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(SettingsPalette.content)
    }
}
