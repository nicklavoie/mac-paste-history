import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, ClipboardMonitorDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private let settingsStore = SettingsStore()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private lazy var clipboardMonitor = ClipboardMonitor(store: store)
    private lazy var settingsWindowController = SettingsWindowController(settingsStore: settingsStore)

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureShortcut()

        clipboardMonitor.delegate = self
        clipboardMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        HotKeyManager.shared.unregister()
    }

    func clipboardMonitorDidCaptureItem(_ item: ClipboardHistoryItem) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        TextPreviewController.shared.hide()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste History")
            button.imagePosition = .imageOnly
        }

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func configureShortcut() {
        HotKeyManager.shared.action = { [weak self] in
            self?.showStatusMenu()
        }
        HotKeyManager.shared.register(settingsStore.hotKey)

        settingsWindowController.onHotKeyChanged = { hotKey in
            HotKeyManager.shared.register(hotKey)
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        button.performClick(nil)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if store.items.isEmpty {
            let emptyItem = NSMenuItem(title: "No clipboard history yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, item) in store.items.enumerated() {
                menu.addItem(menuItem(for: item, index: index))
            }
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = launchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !store.items.isEmpty
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Paste History", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func menuItem(for item: ClipboardHistoryItem, index: Int) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: item.displayTitle,
            action: #selector(restoreHistoryItem(_:)),
            keyEquivalent: index < 9 ? "\(index + 1)" : ""
        )
        menuItem.target = self
        menuItem.representedObject = item.id.uuidString

        switch item.kind {
        case .text:
            let textView = TextHistoryMenuItemView(item: item, detail: detailText(for: item))
            textView.onSelect = { [weak self, weak menu] in
                self?.restore(item)
                menu?.cancelTracking()
            }
            menuItem.view = textView
        case .image:
            menuItem.toolTip = tooltip(for: item)
            menuItem.attributedTitle = attributedTitle(for: item)
            menuItem.image = imageThumbnail(for: item) ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        case .files:
            menuItem.toolTip = tooltip(for: item)
            menuItem.attributedTitle = attributedTitle(for: item)
            menuItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        }

        return menuItem
    }

    private func attributedTitle(for item: ClipboardHistoryItem) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: item.displayTitle,
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        let age = relativeDateFormatter.localizedString(for: item.createdAt, relativeTo: Date())
        let subtitle = "\n\(item.subtitle) · \(age)"
        title.append(NSAttributedString(
            string: subtitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        return title
    }

    private func detailText(for item: ClipboardHistoryItem) -> String {
        let age = relativeDateFormatter.localizedString(for: item.createdAt, relativeTo: Date())
        return "\(item.subtitle) · \(age)"
    }

    private func tooltip(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .text:
            return item.text ?? ""
        case .image:
            return item.title
        case .files:
            return (item.filePaths ?? []).joined(separator: "\n")
        }
    }

    private func imageThumbnail(for item: ClipboardHistoryItem) -> NSImage? {
        guard let url = store.imageURL(for: item),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    @objc private func restoreHistoryItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let uuid = UUID(uuidString: id),
              let item = store.items.first(where: { $0.id == uuid }) else {
            return
        }
        restore(item)
    }

    private func restore(_ item: ClipboardHistoryItem) {
        TextPreviewController.shared.hide()
        clipboardMonitor.restore(item)
    }

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func clearHistory() {
        store.clear()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let shouldEnable = sender.state != .on
        do {
            try launchAtLoginManager.setEnabled(shouldEnable)
        } catch {
            showLaunchAtLoginError(error)
        }
        rebuildMenu()
    }

    private func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Launch at login could not be changed"
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
