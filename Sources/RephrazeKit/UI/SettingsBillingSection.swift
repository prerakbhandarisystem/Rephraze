import SwiftUI

/// The "Plans and Billing" section.
///
/// ## Two different bills, and only one of them is ours
/// Rephraze charges nothing and has no way to. The tokens are billed by OpenAI
/// against the key in Account, directly, with nothing passing through us — so
/// the spend belongs on OpenAI's page and this one links to it rather than
/// printing an estimate it would be guessing at.
///
/// What *is* ours is the allowance: a fixed number of rewrites that land in
/// your text. It is shown in full, including the fact that nothing stops when
/// it runs out, because a counter that hints at a wall it does not have is
/// worse than no counter.
// MARK: - Plans and Billing

struct BillingTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                planRow
            } header: {
                Text("Your plan")
            } footer: {
                Text("""
                    A rewrite counts when it goes into your text. Reading all four and \
                    taking none costs nothing, a rewrite you dismiss costs nothing, and \
                    one that fails on the way back costs nothing — you were given \
                    nothing, so you are charged nothing.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Label(
                    "Nothing stops working at \(UsageQuota.allowance). The count is here so the number is not a surprise later.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("When it runs out")
            } footer: {
                Text("""
                    There is no paid plan to move to yet. When there is, it will be \
                    described here before anything changes about what you already have.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Billed by") {
                    Text("OpenAI, directly")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Charged to") {
                    Text(model.hasStoredKey ? "The key in Account" : "No key yet")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Model in use") {
                    Text(model.model)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Open OpenAI Usage", action: model.openOpenAIBilling)
                }
            } header: {
                Text("What it costs")
            } footer: {
                Text("""
                    Rephraze takes no payment and holds no card. Your key is billed by \
                    OpenAI for the tokens each rewrite uses, on their page rather than \
                    this one — which is also the only place the real number lives, so we \
                    link to it instead of estimating it. Turning off “write the four \
                    versions at the same time” in General spends less per rewrite.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsContentBackground()
        .onAppear { model.refresh() }
    }

    /// What is left of the allowance, and how much of it has gone.
    private var planRow: some View {
        let quota = model.quota

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Free")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(quota.used) of \(UsageQuota.allowance) used")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(
                value: Double(min(quota.used, UsageQuota.allowance)),
                total: Double(UsageQuota.allowance)
            )
            .tint(quota.isRunningLow ? .orange : .accentColor)

            Text(quota.isExhausted
                 ? "All \(UsageQuota.allowance) used — rewrites still work"
                 : "\(quota.remaining) rewrites left")
                .font(.callout)
                .foregroundStyle(quota.isRunningLow ? Color.orange : Color.secondary)
        }
        .padding(.vertical, 3)
    }
}
