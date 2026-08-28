import SwiftUI

/// The "Writing style" section: the adaptive wizard, and the description it
/// produces. Split out of SettingsView so each section is one file you can
/// read end to end.
// MARK: - Writing style

/// A short adaptive wizard that works out how someone writes, then hands them
/// the description it produced.
///
/// Questions are skipped once earlier answers imply them, so "formal" never
/// gets asked about emoji. Where several answers are genuinely compatible --
/// you can write in both Slack and email -- the question takes several.
struct StyleTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    if let question = model.currentQuestion {
                        questionCard(question)
                    } else {
                        resultCard
                    }
                }
                .padding(22)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Divider()

            HStack(spacing: 10) {
                if model.canGoBack {
                    Button("Back", action: model.goBack)
                }

                // Always available once anything has been answered, so nobody
                // is stuck with a set of answers they regret.
                if model.canStartOver {
                    Button("Start over") {
                        withAnimation(.easeOut(duration: 0.15)) { model.startOver() }
                    }
                }

                Spacer()

                if model.canAdvance {
                    Button("Continue", action: model.advance)
                        .keyboardShortcut(.defaultAction)
                } else if model.wizardIsComplete || model.hasStyle {
                    Button("Save style", action: model.saveStyle)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Teach it how you write")
                .font(.title3.weight(.semibold))
            Text("""
                Answer a few questions and Rephraze will rewrite in your style \
                instead of offering four generic tones. You can edit the result \
                afterwards, or write it yourself.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func questionCard(_ question: VoiceQuestion) -> some View {
        let progress = model.wizardProgress

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Question \(progress.asked + 1) of about \(max(progress.total, progress.asked + 1))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if question.allowsMultiple {
                    Text("Choose any")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(question.prompt)
                    .font(.headline)
                if !question.help.isEmpty {
                    Text(question.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 8) {
                ForEach(question.options) { option in
                    optionRow(question, option)
                }
            }
        }
    }

    private func optionRow(_ question: VoiceQuestion, _ option: VoiceOption) -> some View {
        let selected = model.isSelected(question.id, option.id)

        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                model.select(question, option.id)
            }
        } label: {
            HStack(spacing: 11) {
                // A tick box for multi-answer questions, a chevron for the
                // single-answer ones that move straight on.
                if question.allowsMultiple {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if !question.allowsMultiple {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? AnyShapeStyle(.tint.opacity(0.5)) : AnyShapeStyle(.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("This is how Rephraze will write for you")
                    .font(.headline)
            }

            Text("Edit it freely — it is just instructions, in plain English.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $model.styleText)
                .font(.system(size: 12.5))
                .frame(minHeight: 150)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )

            if !model.styleAnswers.isEmpty {
                Button("Rebuild from my answers", action: model.regenerateStyleText)
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Divider().padding(.vertical, 2)

            Toggle("Use my style instead of the four tones", isOn: $model.styleEnabled)
                .font(.callout)

            Text("""
                While this is on, ⌥⌥ returns one rewrite in your style. Turn it \
                off to go back to the four options without losing what you wrote.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
