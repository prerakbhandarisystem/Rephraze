import SwiftUI

/// The floating picker: four rewrites, pick one.
///
/// ## Sized to be read, not just glanced at
/// You are choosing between four blocks of prose, so the text has to be
/// comfortable to actually read -- a cramped panel forces a decision on a
/// half-read sentence. Hence the width, the reading-sized body font, and the
/// original kept visible at the top to compare against.
struct ResultPanelView: View {

    @ObservedObject var model: ResultPanelModel
    @State private var hovered: RephraseVariant?
    @State private var hoveredLanguage: TargetLanguage?
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
            // Thick material reads as a real floating surface rather than a
            // translucent sheet over whatever happens to be behind it.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thickMaterial)
                .overlay {
                    // A barely-there tint from the top, so the panel has a
                    // direction of light instead of sitting flat.
                    LinearGradient(
                        colors: [.white.opacity(0.10), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            // Two hairlines: a light one to lift the top edge, a dark one to
            // define the panel against a light background.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.black.opacity(0.16), lineWidth: 0.5)
                .blendMode(.multiply)
        }
        // Layered shadow: a tight contact shadow plus a wide soft one, which is
        // what stops it looking like a rectangle with a blur behind it.
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.26), radius: 40, y: 18)
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
                // The mark, on a tinted chip -- the same wand as the app icon
                // and the menu bar, so all three read as one thing.
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 11, weight: .semibold))
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
                        .background(.primary.opacity(0.07), in: Capsule())
                        .overlay { Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5) }
                }

                if let language = model.activeLanguage {
                    Text(language.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.14), in: Capsule())
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
                        .fill(.primary.opacity(0.04))
                }
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 7, bottomLeadingRadius: 7,
                        style: .continuous
                    )
                    .fill(.primary.opacity(0.16))
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
                                .background(.quaternary.opacity(0.7), in: Capsule())
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.tint.opacity(0.13)) : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isHovered ? AnyShapeStyle(.tint.opacity(0.55)) : AnyShapeStyle(.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.tint.opacity(0.13))
                                    : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isHovered ? AnyShapeStyle(.tint.opacity(0.55)) : AnyShapeStyle(.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.tint.opacity(0.13))
                                    : AnyShapeStyle(.quaternary.opacity(0.35)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isHovered ? AnyShapeStyle(.tint.opacity(0.55)) : AnyShapeStyle(.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .onHover { hoveredLanguage = $0 ? language : nil }
        .animation(.easeOut(duration: 0.14), value: model.translationComplete)
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
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered
                          ? AnyShapeStyle(Color.accentColor.opacity(0.11))
                          : AnyShapeStyle(.primary.opacity(choosable ? 0.055 : 0.028)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isHovered ? AnyShapeStyle(Color.accentColor.opacity(0.50))
                                  : AnyShapeStyle(.white.opacity(choosable ? 0.10 : 0.04)),
                        lineWidth: isHovered ? 1 : 0.5
                    )
            }
            // An accent rail on the hovered card. Colour alone is easy to miss
            // on a translucent panel over arbitrary content; an edge is not.
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 12, bottomLeadingRadius: 12, style: .continuous
                )
                .fill(Color.accentColor)
                .frame(width: isHovered ? 3 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(isHovered ? 0.10 : 0), radius: 6, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                highlighted ? AnyShapeStyle(.tint)
                    : active ? AnyShapeStyle(.primary.opacity(0.75)) : AnyShapeStyle(.tertiary)
            )
            .frame(width: 24, height: 24)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: highlighted
                                ? [.accentColor.opacity(0.30), .accentColor.opacity(0.16)]
                                : [.primary.opacity(active ? 0.13 : 0.05),
                                   .primary.opacity(active ? 0.07 : 0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        highlighted ? Color.accentColor.opacity(0.45)
                                    : .white.opacity(active ? 0.22 : 0.08),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: .black.opacity(active ? 0.12 : 0), radius: 1, y: 0.5)
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
                .foregroundStyle(choosable ? .primary : .secondary)

            Text(variant.subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            // How much shorter or longer this option is. The reason to pick
            // "Concise" is usually the number, so show the number.
            if isComplete, let delta = lengthDelta(for: text) {
                Text(delta)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.07), in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.5) }
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
                .font(.system(size: 13.5))
                .lineSpacing(4)
                .foregroundStyle(isComplete ? .primary : .secondary)
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
                .fill(.primary.opacity(0.08))
                .frame(width: width, height: 9)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .primary.opacity(0.10), .clear],
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

    /// Type an extra instruction and rewrite again, without starting over.
    ///
    /// The panel does not hold focus by default, so the box is inert until the
    /// user asks for it -- Tab, or a click. That request activates the app;
    /// leaving the box hands focus straight back.
    private var refineBox: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
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
                    Text(model.isEditing
                         ? "Shorter, no jargon, keep the link…"
                         : "Press ⇥ to add an instruction and rewrite")
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
                ? AnyShapeStyle(.tint.opacity(0.07))
                : AnyShapeStyle(.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.beginEditing() }
        // Focus follows the model, which is driven by the window becoming key.
        .onChange(of: model.isEditing) { _, editing in
            inputFocused = editing
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 14) {
            switch model.state {
            case .personal, .translating:
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
                hint("⇥", "refine")
                hint("esc", model.isEditing ? "stop editing" : "dismiss")
            }

            Spacer()
            if !model.isEditing {
                Text(model.isChoosingLanguage
                     ? "written straight into that language"
                     : "or keep typing to carry on")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.65))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.primary.opacity(0.11), .primary.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
