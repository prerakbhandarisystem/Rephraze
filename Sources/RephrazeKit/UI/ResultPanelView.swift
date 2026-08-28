import SwiftUI

/// The surface every selectable row in the panel sits on.
///
/// Defined once. It used to be written out at each card, which is not just
/// extra code but actively misleading: a styling change applied to one copy
/// looks like a change that did not work, because the other three still show
/// the old treatment. That happened.
fileprivate struct PanelCardSurface: ViewModifier {

    /// Rows are either full-width prose or a cell in the ten-language grid.
    /// Those genuinely want different density, so it is a named choice rather
    /// than four sets of numbers that drifted apart.
    enum Density {
        case standard, compact

        var horizontal: CGFloat { self == .standard ? 15 : 11 }
        var vertical: CGFloat { self == .standard ? 13 : 9 }
        var radius: CGFloat { self == .standard ? 13 : 11 }
    }

    var isHovered: Bool
    var density: Density

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: density.radius, style: .continuous)

        return content
            .padding(.horizontal, density.horizontal)
            .padding(.vertical, density.vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(isHovered ? PanelPalette.cardHover : PanelPalette.card) }
            // No outline at rest. The card is a step darker than the surface
            // and that step is enough -- an outline round every row turns a
            // list of four sentences into a form with four boxes on it. The
            // accent edge comes back on hover, where it is doing real work.
            .overlay {
                shape.strokeBorder(
                    isHovered ? PanelPalette.accent.opacity(0.45) : .clear,
                    lineWidth: isHovered ? 1 : 0
                )
            }
            // An accent rail on the hovered row. A tint alone is easy to miss
            // against arbitrary content behind the panel; an edge is not.
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: density.radius,
                    bottomLeadingRadius: density.radius,
                    style: .continuous
                )
                .fill(PanelPalette.accent)
                .frame(width: isHovered ? 3 : 0)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(isHovered ? 0.07 : 0), radius: 6, y: 2)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// Draw this row as a selectable card in the result panel.
    fileprivate func panelCard(
        isHovered: Bool,
        density: PanelCardSurface.Density = .standard
    ) -> some View {
        modifier(PanelCardSurface(isHovered: isHovered, density: density))
    }
}

/// The floating picker: four rewrites, pick one.
///
/// ## Sized to be read, not just glanced at
/// You are choosing between four blocks of prose, so the text has to be
/// comfortable to actually read -- a cramped panel forces a decision on a
/// half-read sentence. Hence the width, the reading-sized body font, and the
/// original kept visible at the top to compare against.
/// The panel's colours, in one place.
///
/// A white panel cannot borrow the system's semantic colours: those flip with
/// the user's appearance setting, and light-grey-on-white text is unreadable
/// the moment someone switches to dark mode. So the panel fixes its own light
/// palette and forces a light colour scheme over its contents, which also means
/// every control inside -- including ones this file does not own -- resolves to
/// dark-on-light rather than the reverse.
enum PanelPalette {
    /// The panel itself: warm off-white, not white.
    ///
    /// Every value below has red > green > blue. That ordering is the whole
    /// point and it is easy to lose -- the previous palette described itself as
    /// warm while having blue at 1.0 and red at 0.996, which is cool by a hair.
    /// A paper-warm surface reads as a considered object; a cool one reads as
    /// an untinted default, and next to macOS chrome it reads as a hole.
    static let surface = Color(red: 0.992, green: 0.988, blue: 0.980)
    /// Cards sitting on the surface. Close to it on purpose -- the step between
    /// the two is what separates them, so the cards need no outline.
    static let card = Color(red: 0.961, green: 0.949, blue: 0.933)
    /// Hover reaches for the accent rather than just going darker, so the row
    /// under the pointer is warm-lilac instead of grubby.
    static let cardHover = Color(red: 0.945, green: 0.937, blue: 0.953)
    static let hairline = Color(red: 0.906, green: 0.890, blue: 0.867)

    /// Body text. Near-black rather than black: pure #000 on white is harsh
    /// over a long paragraph, which is exactly what this panel shows. Warm to
    /// match the surface -- cool grey on cream looks like a rendering fault.
    static let text = Color(red: 0.114, green: 0.106, blue: 0.094)
    static let secondary = Color(red: 0.412, green: 0.392, blue: 0.361)
    static let tertiary = Color(red: 0.600, green: 0.576, blue: 0.541)

    /// The indigo from the app icon, so panel and icon are one product.
    static let accent = Color(red: 0.361, green: 0.353, blue: 0.855)
}

struct ResultPanelView: View {

    @ObservedObject var model: ResultPanelModel
    @State private var hovered: RephraseVariant?
    @State private var hoveredLanguage: TargetLanguage?
    @State private var hoveredTurn: UUID?
    @FocusState private var inputFocused: Bool
    /// Drives the placeholder sweep while variants are still arriving.
    @State private var shimmer = false

    /// Sized against the actual display rather than a fixed number.
    ///
    /// The panel exists to be read in one glance. Scrolling to compare option 1
    /// against option 4 defeats the point, so on a large screen it takes the
    /// room it needs.

    /// Wider screens get a wider panel: longer lines mean fewer wrapped rows,
    /// which is the cheapest way to make the whole set fit without scrolling.
    private var panelWidth: CGFloat {
        let screen = NSScreen.main?.visibleFrame.width ?? 1440
        return min(880, max(620, screen * 0.44))
    }

    /// How tall the list of options may grow before it starts scrolling.
    ///
    /// Leaves room for the header, footer and a margin, so the panel stays on
    /// screen even when all four rewrites are long.
    private var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 900
        return min(1200, max(460, screen * 0.78))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            content
            if !model.isChoosingLanguage {
                Divider().opacity(0.6)
                refineBox
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: panelWidth)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(PanelPalette.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            // Half a point, not one. The shadow already says where the panel
            // ends; the outline is only here for the case where it lands on
            // something dark, and a full point of it reads as a drawn box.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(PanelPalette.hairline.opacity(0.8), lineWidth: 0.5)
        }
        // Layered shadow: a tight contact shadow under a wide soft one. On an
        // opaque panel this is the only thing separating it from a white window
        // behind it, so it does more work here than it did before.
        //
        // Wider and lighter than it was. A short dense shadow reads as a box
        // sitting on the screen; a long faint one reads as a surface floating
        // above it, which is the difference being aimed at.
        .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.15), radius: 52, y: 22)
        // Everything inside is dark-on-light regardless of system appearance.
        .environment(\.colorScheme, .light)
        .tint(PanelPalette.accent)
        .animation(.smooth(duration: 0.22), value: model.stateID)
        .onAppear {
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // The mark, on a tinted chip -- the same damped wave the app
                // icon and the menu bar draw, so they read as one thing.
                RephrazeMarkView(size: 16)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.42, green: 0.42, blue: 0.96),
                                        Color(red: 0.66, green: 0.31, blue: 0.90),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

                Text("Rephraze")
                    .font(.system(size: 13, weight: .semibold))
                    .kerning(-0.1)

                if !model.appName.isEmpty {
                    Text(model.appName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(PanelPalette.card, in: Capsule())
                        .overlay { Capsule().strokeBorder(PanelPalette.hairline, lineWidth: 0.5) }
                }

                if let language = model.activeLanguage {
                    Text(language.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PanelPalette.accent.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 0)

                if case .streaming = model.state, !model.isSettled {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }

            // What you wrote, to compare the options against. Labelled and set
            // in its own recess, so it cannot be mistaken for one of the
            // options -- it is the one block here you must not pick.
            if !model.currentOriginal.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOU WROTE")
                        .font(.system(size: 9, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(.tertiary)

                    Text(model.currentOriginal)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 10)
                .padding(.vertical, 7)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PanelPalette.card)
                }
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 7, bottomLeadingRadius: 7,
                        style: .continuous
                    )
                    .fill(PanelPalette.accent.opacity(0.35))
                    .frame(width: 2.5)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Writing four versions…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 26)

        case let .failed(message):
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)

        case .personal:
            ScrollView {
                personalCard
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
            }
            .frame(maxHeight: maxListHeight)

        case .chat:
            chatTranscript

        case .languages:
            languageList

        case let .translating(language):
            ScrollView {
                translationCard(language: language)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
            }
            .frame(maxHeight: maxListHeight)

        case .streaming:
            ScrollView {
                VStack(spacing: 7) {
                    // Every variant always gets a row, in a fixed order, so the
                    // number beside it cannot move as results land.
                    ForEach(Array(RephraseVariant.allCases.enumerated()), id: \.element) { index, variant in
                        let slot = model.slots[variant] ?? VariantSlot()
                        row(
                            index: index + 1,
                            variant: variant,
                            text: slot.text,
                            isComplete: slot.isComplete,
                            error: slot.error
                        )
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: maxListHeight)

        case let .ready(set):
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(set.available.enumerated()), id: \.element.variant) { index, option in
                        row(
                            index: index + 1,
                            variant: option.variant,
                            text: option.text,
                            isComplete: true,
                            error: nil
                        )
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: maxListHeight)
        }
    }

    // MARK: - Personal voice

    /// One rewrite, in the user's own voice. No numbering to compare against,
    /// so the row is a single confirm-or-dismiss card.
    private var personalCard: some View {
        let ready = model.personalIsChoosable
        let hasText = !model.personalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isHovered = hovered == .polished && ready   // any sentinel; one card only

        return Button {
            model.choosePersonal()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                keycap(1, active: ready, highlighted: isHovered)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 11))
                            .foregroundStyle(ready ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .frame(width: 14)

                        Text("In your style")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(ready ? .primary : .secondary)

                        if model.personalComplete,
                           let delta = lengthDelta(for: model.personalText) {
                            Text(delta)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.white, in: Capsule())
                        }

                        Spacer(minLength: 0)
                    }

                    body(
                        text: model.personalText,
                        hasText: hasText,
                        isComplete: model.personalComplete,
                        error: nil
                    )
                }

                Spacer(minLength: 0)
            }
            .panelCard(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .onHover { hovered = $0 ? .polished : nil }
        .animation(.easeOut(duration: 0.14), value: model.personalComplete)
    }

    // MARK: - Languages

    /// The ten languages, on the ten number keys.
    ///
    /// Two columns rather than one long list. Ten stacked rows would make this
    /// menu taller than the rewrites it covers, and it is a menu -- you are
    /// looking for one known language, not reading all ten.
    private var languageList: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
            alignment: .leading,
            spacing: 7
        ) {
            ForEach(TargetLanguage.allCases) { language in
                languageRow(language)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
    }

    /// One language: the key that picks it, its own name, then ours.
    ///
    /// The endonym leads because that is the string someone scanning for their
    /// language actually recognises -- you find "日本語" without reading, where
    /// "Japanese" has to be read.
    private func languageRow(_ language: TargetLanguage) -> some View {
        let isHovered = hoveredLanguage == language

        return Button {
            model.onChooseLanguage?(language)
        } label: {
            HStack(spacing: 10) {
                keycap(language.shortcutDigit, active: true, highlighted: isHovered)

                VStack(alignment: .leading, spacing: 1) {
                    Text(language.endonym)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(language.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .panelCard(isHovered: isHovered, density: .compact)
        }
        .buttonStyle(.plain)
        .onHover { hoveredLanguage = $0 ? language : nil }
        .animation(.easeOut(duration: 0.10), value: isHovered)
    }

    /// The message written in the chosen language, as it arrives.
    ///
    /// No length badge here, unlike the rewrite rows. A percentage against the
    /// original would be comparing character counts across two writing systems,
    /// where the same sentence is legitimately half the length in Japanese and
    /// half again as long in German -- a number that means nothing but looks
    /// like it means something.
    private func translationCard(language: TargetLanguage) -> some View {
        let ready = model.translationIsChoosable
        let hasText = !model.translationText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isHovered = hoveredLanguage == language && ready

        return Button {
            model.chooseTranslation()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                keycap(1, active: ready, highlighted: isHovered)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "character.bubble")
                            .font(.system(size: 11))
                            .foregroundStyle(ready ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .frame(width: 14)

                        Text("In \(language.title)")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(ready ? .primary : .secondary)

                        Text(language.endonym)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 0)
                    }

                    body(
                        text: model.translationText,
                        hasText: hasText,
                        isComplete: model.translationComplete,
                        error: nil,
                        isRTL: language.isRightToLeft
                    )
                }

                Spacer(minLength: 0)
            }
            .panelCard(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .onHover { hoveredLanguage = $0 ? language : nil }
        .animation(.easeOut(duration: 0.14), value: model.translationComplete)
    }

    // MARK: - The conversation

    /// The exchange so far: what you asked for, and what came back.
    ///
    /// Scrolled to the newest turn as it arrives, including while it is still
    /// streaming. The panel grows to fit and only starts scrolling once it runs
    /// out of screen, so a short conversation is simply all visible.
    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.chat.turns.enumerated()), id: \.element.id) { index, turn in
                        chatRow(turn, isLatest: index == model.chat.turns.count - 1)
                            .id(turn.id)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: maxListHeight)
            // No animation on either: this fires once per streamed chunk, and
            // an animated scroll per token never finishes one before the next
            // begins, which reads as the text sliding around rather than
            // arriving.
            .onChange(of: model.chat.turns.count) { _, _ in scrollToLatest(proxy) }
            .onChange(of: model.chat.turns.last?.text) { _, _ in scrollToLatest(proxy) }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = model.chat.turns.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    @ViewBuilder
    private func chatRow(_ turn: ChatTurn, isLatest: Bool) -> some View {
        switch turn.speaker {
        case .you: askedRow(turn)
        case .rephraze: repliedRow(turn, isLatest: isLatest)
        }
    }

    /// What the user asked for.
    ///
    /// Tinted and set to the right, so running an eye down the transcript
    /// separates the two voices without having to read either of them.
    private func askedRow(_ turn: ChatTurn) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 72)

            Text(turn.text)
                .font(.system(size: 12.5))
                .foregroundStyle(PanelPalette.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    PanelPalette.accent.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PanelPalette.accent.opacity(0.22), lineWidth: 0.5)
                }
        }
    }

    /// A rewrite that takes the conversation so far into account.
    ///
    /// Only the newest one carries the `1` key and the label. The ones above it
    /// are dimmed but still clickable: numbering a growing transcript would
    /// move every key each time a message is sent, and this panel's one firm
    /// rule is that the number beside a rewrite cannot move under your finger.
    private func repliedRow(_ turn: ChatTurn, isLatest: Bool) -> some View {
        let choosable = turn.isChoosable
        let isHovered = hoveredTurn == turn.id && choosable

        return Button {
            model.choose(turn)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if isLatest {
                    keycap(1, active: choosable, highlighted: isHovered)
                } else {
                    // Hold the gutter open, so every reply's text starts on the
                    // same line down the panel whether it has a key or not.
                    Color.clear.frame(width: 24, height: 1)
                }

                VStack(alignment: .leading, spacing: 5) {
                    if isLatest {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    choosable ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary)
                                )
                                .frame(width: 14)

                            Text("With your context")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(choosable ? .primary : .secondary)

                            if turn.isComplete, let delta = lengthDelta(for: turn.text) {
                                Text(delta)
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 2)
                                    .background(Color.white, in: Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(PanelPalette.hairline, lineWidth: 0.5)
                                    }
                            }

                            Spacer(minLength: 0)
                        }
                    }

                    body(
                        text: turn.text,
                        hasText: turn.hasText,
                        isComplete: turn.isComplete,
                        error: turn.error
                    )
                }

                Spacer(minLength: 0)
            }
            .panelCard(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!choosable)
        .onHover { hoveredTurn = $0 ? turn.id : nil }
        // Superseded answers recede rather than disappear.
        .opacity(isLatest ? 1 : 0.62)
        .animation(.smooth(duration: 0.20), value: turn.isComplete)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    // MARK: - One option

    /// A row in any of its states: waiting, mid-stream, done, or failed.
    @ViewBuilder
    private func row(
        index: Int,
        variant: RephraseVariant,
        text: String,
        isComplete: Bool,
        error: String?
    ) -> some View {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let choosable = isComplete && hasText && error == nil
        let isHovered = hovered == variant && choosable

        Button {
            model.choose(variant)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                keycap(index, active: choosable, highlighted: isHovered)

                VStack(alignment: .leading, spacing: 5) {
                    label(variant, choosable: choosable, text: text, isComplete: isComplete)
                    body(text: text, hasText: hasText, isComplete: isComplete, error: error)
                }

                Spacer(minLength: 0)
            }
            .panelCard(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!choosable)
        .onHover { hovered = $0 ? variant : nil }
        // Landing text should settle in, not snap.
        .animation(.smooth(duration: 0.20), value: isComplete)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    /// The number you press, drawn as a key.
    /// The number you press, drawn as a physical key.
    ///
    /// Worth the detail: it is the only affordance telling you the panel is
    /// keyboard-driven, and a flat grey square reads as a label rather than a
    /// key you can press.
    private func keycap(_ index: Int, active: Bool, highlighted: Bool) -> some View {
        Text("\(index)")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(
                highlighted ? AnyShapeStyle(Color.white)
                    : active ? AnyShapeStyle(PanelPalette.text) : AnyShapeStyle(PanelPalette.tertiary)
            )
            .frame(width: 24, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(highlighted ? PanelPalette.accent : Color.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        highlighted ? PanelPalette.accent : PanelPalette.hairline,
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(active ? 0.08 : 0), radius: 1, y: 0.5)
            .padding(.top, 1)
    }

    private func label(
        _ variant: RephraseVariant,
        choosable: Bool,
        text: String,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: variant.symbol)
                .font(.system(size: 11))
                .foregroundStyle(choosable ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 14)

            Text(variant.title)
                .font(.system(size: 12.5, weight: .semibold))
                .kerning(-0.1)
                .foregroundStyle(choosable ? PanelPalette.text : PanelPalette.tertiary)

            Text(variant.subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(PanelPalette.tertiary)

            // How much shorter or longer this option is. The reason to pick
            // "Concise" is usually the number, so show the number.
            if isComplete, let delta = lengthDelta(for: text) {
                Text(delta)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(Color.white, in: Capsule())
                    .overlay { Capsule().strokeBorder(PanelPalette.hairline, lineWidth: 0.5) }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func body(
        text: String,
        hasText: Bool,
        isComplete: Bool,
        error: String?,
        isRTL: Bool = false
    ) -> some View {
        if let error {
            Text(error)
                .font(.system(size: 11.5))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if hasText {
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundStyle(isComplete ? PanelPalette.text : PanelPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // Arabic has to be laid out right to left, not merely rendered
                // with its own glyphs: left-aligned Arabic wraps its lines from
                // the wrong edge, which is the paragraph equivalent of reading
                // a page from the back.
                .multilineTextAlignment(isRTL ? .trailing : .leading)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                .textSelection(.enabled)
        } else {
            // Placeholder bars, so the row keeps its shape while it waits and
            // the panel does not jump as text lands.
            VStack(alignment: .leading, spacing: 5) {
                placeholderBar(widthFraction: 0.92)
                placeholderBar(widthFraction: 0.58)
            }
            .padding(.vertical, 2)
        }
    }

    /// A bar that sweeps, so a row waiting on the network looks alive.
    ///
    /// Cheaper than a spinner per row and quieter: four spinners in a column
    /// reads as four separate problems.
    private func placeholderBar(widthFraction: CGFloat) -> some View {
        GeometryReader { geo in
            let width = geo.size.width * widthFraction
            RoundedRectangle(cornerRadius: 4)
                .fill(PanelPalette.card)
                .frame(width: width, height: 9)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.clear, PanelPalette.hairline, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.45)
                        .offset(x: shimmer ? width * 0.85 : -width * 0.45)
                        .frame(width: width, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
        }
        .frame(height: 9)
    }

    /// Percentage change in length against the original, when it is worth saying.
    private func lengthDelta(for text: String) -> String? {
        let original = model.currentOriginal.count
        guard original > 0, !text.isEmpty else { return nil }
        let change = Double(text.count - original) / Double(original)
        guard abs(change) >= 0.05 else { return nil }
        let percent = Int((abs(change) * 100).rounded())
        return change < 0 ? "−\(percent)%" : "+\(percent)%"
    }

    // MARK: - Follow-up input

    /// Type context and rewrite again, without starting over.
    ///
    /// The panel does not hold focus by default, so the box is inert until the
    /// user asks for it -- Tab, or a click. That request activates the app; esc
    /// hands focus straight back. Focus is kept between messages, so a
    /// conversation reads as one, and only the first message costs a ⇥.
    private var refineBox: some View {
        HStack(spacing: 9) {
            Image(systemName: model.isChatting
                  ? "bubble.left.and.text.bubble.right"
                  : "arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 11))
                .foregroundStyle(model.isEditing ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

            ZStack(alignment: .leading) {
                TextField("", text: $model.refineText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($inputFocused)
                    .onSubmit { model.submitRefinement() }
                    .disabled(!model.isEditing)

                if model.refineText.isEmpty {
                    Text(composerPrompt)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }

            if model.isEditing && !model.refineText.isEmpty {
                Button {
                    model.submitRefinement()
                } label: {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            model.isEditing
                ? AnyShapeStyle(PanelPalette.accent.opacity(0.06))
                : AnyShapeStyle(.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.beginEditing() }
        // Focus follows the model, which is driven by the window becoming key.
        .onChange(of: model.isEditing) { _, editing in
            inputFocused = editing
        }
    }

    /// What the empty box invites you to do.
    ///
    /// Different once a conversation exists: the first message has to explain
    /// that the box is there at all, and after that it is obviously a chat and
    /// the examples are worth more than the instructions.
    private var composerPrompt: String {
        switch (model.isEditing, model.isChatting) {
        case (true, true):   return "Mention the deadline, warmer, keep the link…"
        case (true, false):  return "Shorter, no jargon, keep the link…"
        case (false, true):  return "Press ⇥ to add more"
        case (false, false): return "Press ⇥ to add context and rewrite"
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 14) {
            if model.isEditing {
                // The panel holds the keyboard, so none of the picker's keys are
                // live. Still offering "1 apply" here would be a lie that costs
                // the user a stray character in the middle of a sentence.
                hint("⏎", "send")
                hint("esc", "done")
            } else {
                switch model.state {
                case .personal, .translating, .chat:
                    hint("1", "apply")
                case .languages:
                    hint("1–0", "write in")
                default:
                    hint("1–4", "apply")
                }

                if model.isChoosingLanguage {
                    hint("esc", "back")
                } else {
                    hint("⌥T", "translate")
                    hint("⇥", model.isChatting ? "add more" : "refine")
                    hint("esc", "dismiss")
                }
            }

            Spacer()
            if !model.isEditing {
                Text(footerNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var footerNote: String {
        if model.isChoosingLanguage { return "written straight into that language" }
        if model.isChatting { return "click any answer above to use it" }
        return "or keep typing to carry on"
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(PanelPalette.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(PanelPalette.hairline, lineWidth: 0.5)
                }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
