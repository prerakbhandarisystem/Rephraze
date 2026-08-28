import SwiftUI

/// The settings window's two tones.
///
/// Taken from the reference this window is being matched to: warm cream for the
/// navigation, a lighter warm off-white for whatever section is open. The
/// separation is the point -- the sidebar is a place you pass through and the
/// content is where you stop, and a single flat background says neither.
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

    /// The open section: lighter, so it reads as sitting on top of the
    /// navigation rather than beside it.
    static let content = Color(red: 0.980, green: 0.973, blue: 0.957)

    /// The line between the two columns, and under the footers.
    static let hairline = Color(red: 0.878, green: 0.859, blue: 0.827)
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
