import SwiftUI

/// The floating picker: four rewrites, pick one.
struct ResultPanelView: View {

    @ObservedObject var model: ResultPanelModel
    @State private var hovered: RephraseVariant?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 22, y: 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.sparkles")
                .foregroundStyle(.tint)
            Text("Rephraze")
                .font(.headline)
            if !model.appName.isEmpty {
                Text("· \(model.appName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Writing four versions…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 22)

        case let .failed(message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)

        case let .ready(set):
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(set.available.enumerated()), id: \.element.variant) { index, option in
                        optionRow(index: index + 1, variant: option.variant, text: option.text)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 420)
        }
    }

    private func optionRow(index: Int, variant: RephraseVariant, text: String) -> some View {
        Button {
            model.choose(variant)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // The number you press to pick this one.
                Text("\(index)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: variant.symbol)
                            .font(.caption)
                            .foregroundStyle(.tint)
                        Text(variant.title)
                            .font(.subheadline.weight(.semibold))
                        Text(variant.subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(hovered == variant ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? variant : nil }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            hint("1–4", "pick")
            hint("esc", "cancel")
            Spacer()
            Text("or just keep typing")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
