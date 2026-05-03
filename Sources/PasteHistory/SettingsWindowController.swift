import AppKit

final class SettingsWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let shortcutView: ShortcutCaptureView
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let launchAtLoginStatus = NSTextField(labelWithString: "")
    var onHotKeyChanged: ((HotKey) -> Void)?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        shortcutView = ShortcutCaptureView(hotKey: settingsStore.hotKey)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 270))

        let title = NSTextField(labelWithString: "Paste History Settings")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let shortcutLabel = NSTextField(labelWithString: "Show history")

        let hint = NSTextField(labelWithString: "Click the shortcut field, then press a new key combination.")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        let resetButton = NSButton(title: "Reset to Command + Shift + V", target: nil, action: nil)
        resetButton.bezelStyle = .rounded

        launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off

        launchAtLoginStatus.textColor = .secondaryLabelColor
        launchAtLoginStatus.font = .systemFont(ofSize: 12)
        launchAtLoginStatus.lineBreakMode = .byWordWrapping
        launchAtLoginStatus.maximumNumberOfLines = 2

        let shortcutRow = NSStackView(views: [shortcutLabel, shortcutView])
        shortcutRow.orientation = .horizontal
        shortcutRow.alignment = .centerY
        shortcutRow.spacing = 24

        let shortcutStack = NSStackView(views: [shortcutRow, hint, resetButton])
        shortcutStack.orientation = .vertical
        shortcutStack.alignment = .leading
        shortcutStack.spacing = 10

        let launchStack = NSStackView(views: [launchAtLoginButton, launchAtLoginStatus])
        launchStack.orientation = .vertical
        launchStack.alignment = .leading
        launchStack.spacing = 6

        let rootStack = NSStackView(views: [title, shortcutStack, launchStack])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 24
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            launchAtLoginStatus.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])

        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Paste History Settings"
        window.contentView = contentView
        window.center()

        super.init(window: window)

        updateLaunchAtLoginStatus()

        shortcutView.onShortcutCaptured = { [weak self] hotKey in
            self?.saveHotKey(hotKey)
        }
        resetButton.target = self
        resetButton.action = #selector(resetShortcut)
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(toggleLaunchAtLogin)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off
        updateLaunchAtLoginStatus()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func saveHotKey(_ hotKey: HotKey) {
        settingsStore.hotKey = hotKey
        onHotKeyChanged?(hotKey)
    }

    @objc private func resetShortcut() {
        let hotKey = HotKey.defaultShortcut
        shortcutView.setHotKey(hotKey)
        saveHotKey(hotKey)
    }

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable = launchAtLoginButton.state == .on

        do {
            try launchAtLoginManager.setEnabled(shouldEnable)
            launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off
            updateLaunchAtLoginStatus()
        } catch {
            launchAtLoginButton.state = launchAtLoginManager.isEnabled ? .on : .off
            launchAtLoginStatus.textColor = .systemRed
            launchAtLoginStatus.stringValue = error.localizedDescription
        }
    }

    private func updateLaunchAtLoginStatus() {
        launchAtLoginStatus.textColor = .secondaryLabelColor
        launchAtLoginStatus.stringValue = launchAtLoginManager.isEnabled
            ? "Paste History will open automatically when you sign in."
            : "Paste History will only open when launched manually."
    }
}
