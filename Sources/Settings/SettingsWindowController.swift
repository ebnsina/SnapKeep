import SwiftUI
import AppKit

/// Hosts the Settings window (a normal titled window since it's a MenuBarExtra app).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let app: AppState

    init(app: AppState) { self.app = app }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: SettingsView(onRebind: { [weak app] in app?.reloadHotkeys() }))
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 440),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "\(Brand.name) Settings"
        win.contentView = hosting
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    let onRebind: () -> Void

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "command") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 440)
    }

    private var general: some View {
        Form {
            Section("Capture") {
                Picker("Image format", selection: $settings.format) {
                    ForEach(AppSettings.ImageFormat.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Delay: \(settings.captureDelay)s", value: $settings.captureDelay, in: 0...15)
                Toggle("Copy to clipboard automatically", isOn: $settings.autoCopy)
                Toggle("Play shutter sound", isOn: $settings.playSound)
            }
            Section("Recording") {
                Picker("Format", selection: $settings.recordFormat) {
                    ForEach(AppSettings.RecordFormat.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Frame rate: \(settings.recordFPS) fps", value: $settings.recordFPS, in: 10...60, step: 5)
                Toggle("Record system audio", isOn: $settings.recordSystemAudio)
            }
            Section("Save location") {
                HStack {
                    Text(settings.saveDirectory.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                    if !settings.saveDirectoryPath.isEmpty {
                        Button("Reset") { settings.saveDirectoryPath = "" }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Global shortcuts") {
                ForEach(HotKeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        KeyRecorderField(binding: settings.binding(for: action)) { newBinding in
                            settings.setBinding(newBinding, for: action)
                            onRebind()
                        }
                    }
                }
            }
            Section {
                Button("Reset to defaults") {
                    settings.resetBindings()
                    onRebind()
                }
            }
            Text("Click a shortcut, then press the new key combination (needs a modifier).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 46)).foregroundStyle(Theme.brandGradient)
                .padding(.bottom, Theme.Space.xs)
            Text(Brand.name).font(.title.bold())
            Text("Version \(Brand.version) (\(Brand.build))")
                .font(.callout).foregroundStyle(.secondary)
            Text("A fast, private screenshot and recording tool for macOS.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(Brand.copyright)
                .font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, Theme.Space.xs)
            Spacer()
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}
