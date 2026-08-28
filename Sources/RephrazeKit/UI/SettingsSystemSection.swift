import SwiftUI

/// The "System" section: how Rephraze sits on the Mac when you are not using it.
///
/// Every switch here is off or quiet by default. This app interrupts you on
/// purpose, dozens of times a day, in whatever you happen to be typing into —
/// an app with that much licence does not also get to start itself, keep a Dock
/// icon and make noise unless it is asked to.
// MARK: - System

struct SystemTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch Rephraze at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: model.setLaunchAtLogin
                ))
                .disabled(!model.canLaunchAtLogin)

                if !model.canLaunchAtLogin {
                    Label(
                        "This build is a bare binary, not an app bundle, so macOS has nothing to register.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Show Rephraze in the Dock", isOn: Binding(
                    get: { model.showsInDock },
                    set: model.setShowsInDock
                ))

                Toggle("Let the panel open over full-screen apps", isOn: Binding(
                    get: { model.panelFollowsFullScreen },
                    set: model.setPanelFollowsFullScreen
                ))
            } header: {
                Text("App settings")
            } footer: {
                Text("""
                    Rephraze lives in the menu bar. A Dock icon is optional and off by \
                    default — hiding it takes effect when this window closes, because a \
                    window with no Dock icon cannot be reached with ⌘-Tab. Turning the \
                    full-screen switch off keeps the panel out of full-screen apps \
                    entirely; the shortcut then does nothing there.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Sound when a rewrite is ready", isOn: Binding(
                    get: { model.soundOnReady },
                    set: model.setSoundOnReady
                ))

                Toggle("Sound when a rewrite fails", isOn: Binding(
                    get: { model.soundOnFailure },
                    set: model.setSoundOnFailure
                ))
            } header: {
                Text("Sound")
            } footer: {
                Text("""
                    Both off to begin with. The panel opens right next to your caret, \
                    which is where you are already looking, so a sound on every rewrite \
                    would be a noise telling you something you can see. Switch one on and \
                    it plays once, here, so you know what you have chosen.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Tell me when a rewrite fails", isOn: Binding(
                    get: { model.notifyOnFailure },
                    set: model.setNotifyOnFailure
                ))
                .disabled(!model.notificationsAvailable)

                Toggle("Tell me when the rewrites run low", isOn: Binding(
                    get: { model.notifyWhenLow },
                    set: model.setNotifyWhenLow
                ))
                .disabled(!model.notificationsAvailable)

                if model.notificationsRefused {
                    Label(
                        "macOS is not allowing notifications from Rephraze. Turn them on in System Settings › Notifications.",
                        systemImage: "bell.slash"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                } else if !model.notificationsAvailable {
                    Label(
                        "This build is a bare binary, not an app bundle, so macOS will not deliver notifications to it.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("""
                    For the moments the panel is not where you are looking. A failure \
                    notice never quotes what you were writing — a banner is shown on a \
                    locked screen and kept in Notification Centre afterwards, and neither \
                    is a place to put your sentences.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsContentBackground()
        .onAppear { model.refresh() }
    }
}
