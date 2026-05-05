import AppKit

private enum HistoryMenuColumn {
    case paste
    case remove
}

private final class KeyboardHandlingMenu: NSMenu {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyDown?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ClipboardMonitorDelegate, NSMenuDelegate {
    private let store = HistoryStore()
    private let settingsStore = SettingsStore()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private lazy var clipboardMonitor = ClipboardMonitor(store: store)
    private lazy var settingsWindowController = SettingsWindowController(settingsStore: settingsStore)

    private var statusItem: NSStatusItem!
    private let menu = KeyboardHandlingMenu()
    private var selectedHistoryItemID: UUID?
    private var selectedHistoryColumn: HistoryMenuColumn = .paste
    private var isKeyboardNavigatingHistory = false
    private var shouldPreserveSelectionOnOpen = false
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
        if shouldPreserveSelectionOnOpen {
            shouldPreserveSelectionOnOpen = false
            if selectedHistoryItemID == nil {
                selectedHistoryItemID = store.items.first?.id
            }
        } else {
            selectedHistoryColumn = .paste
            selectedHistoryItemID = store.items.first?.id
        }
        isKeyboardNavigatingHistory = selectedHistoryItemID != nil
        rebuildMenu()
        if let selectedHistoryItemID,
           let item = store.items.first(where: { $0.id == selectedHistoryItemID }) {
            DispatchQueue.main.async { [weak self] in
                self?.focusSelectedHistoryView()
                self?.showPreview(for: item, near: self?.view(for: selectedHistoryItemID))
            }
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        TextPreviewController.shared.hide()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let uuid = historyItemID(for: item) {
            if !isKeyboardNavigatingHistory {
                selectedHistoryItemID = uuid
                updateHistoryMenuRows()
            }
        }

        guard let item,
              let uuid = historyItemID(for: item),
              let historyItem = store.items.first(where: { $0.id == uuid }),
              historyItem.kind == .text,
              let text = historyItem.text,
              !text.isEmpty else {
            TextPreviewController.shared.hide()
            return
        }

        TextPreviewController.shared.show(
            text: text,
            near: estimatedScreenFrame(for: item, in: menu),
            on: menuScreen()
        )
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste History")
            button.imagePosition = .imageOnly
        }

        menu.delegate = self
        menu.onKeyDown = { [weak self] event in
            self?.handleMenuKeyDown(event) == nil
        }
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
            title: "",
            action: nil,
            keyEquivalent: ""
        )
        let view = HistoryMenuItemView(
            item: item,
            icon: icon(for: item),
            subtitle: detailText(for: item),
            isSelected: selectedHistoryItemID == item.id,
            selectedColumn: selectedHistoryColumn
        )
        view.onSelect = { [weak self] column in
            self?.selectHistoryItem(item.id, column: column, source: .mouse)
        }
        view.onMouseMoved = { [weak self] in
            self?.resumeMouseSelection()
        }
        view.onActivate = { [weak self] in
            self?.restore(item)
        }
        view.onRemove = { [weak self] in
            self?.removeHistoryItem(id: item.id)
        }
        view.onPreview = { [weak self, weak view] in
            self?.showPreview(for: item, near: view)
        }
        view.onKeyDown = { [weak self] event in
            self?.handleMenuKeyDown(event) == nil
        }
        menuItem.view = view
        menuItem.representedObject = item.id.uuidString
        menuItem.toolTip = tooltip(for: item)

        return menuItem
    }

    private func detailText(for item: ClipboardHistoryItem) -> String {
        let age = relativeDateFormatter.localizedString(for: item.createdAt, relativeTo: Date())
        return "\(item.subtitle) · \(age)"
    }

    private func icon(for item: ClipboardHistoryItem) -> NSImage? {
        switch item.kind {
        case .text:
            return NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        case .image:
            return imageThumbnail(for: item) ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        case .files:
            return NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        }
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

    private func estimatedScreenFrame(for item: NSMenuItem, in menu: NSMenu) -> NSRect {
        let menuFrame = menuWindowFrame() ?? fallbackMenuFrame()
        guard let itemIndex = menu.items.firstIndex(of: item) else {
            return NSRect(x: menuFrame.maxX, y: menuFrame.midY - 11, width: 1, height: 22)
        }

        let yOffset = menu.items.prefix(itemIndex).reduce(CGFloat(0)) { $0 + estimatedHeight(for: $1) }
        let itemHeight = estimatedHeight(for: item)
        return NSRect(
            x: menuFrame.minX,
            y: menuFrame.maxY - yOffset - itemHeight,
            width: menuFrame.width,
            height: itemHeight
        )
    }

    private func estimatedHeight(for item: NSMenuItem) -> CGFloat {
        if item.isSeparatorItem {
            return 9
        }
        if let id = item.representedObject as? String,
           UUID(uuidString: id) != nil {
            return HistoryMenuItemView.rowHeight
        }
        return 22
    }

    private func menuWindowFrame() -> NSRect? {
        NSApp.windows
            .filter { $0.isVisible && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
            .first?
            .frame
    }

    private func fallbackMenuFrame() -> NSRect {
        let mouse = NSEvent.mouseLocation
        return NSRect(x: mouse.x - 120, y: mouse.y - 180, width: 260, height: 360)
    }

    private func menuScreen() -> NSScreen {
        let frame = menuWindowFrame() ?? fallbackMenuFrame()
        return NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func handleMenuKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode != 125,
           event.keyCode != 126,
           let activeID = historyItemID(for: menu.highlightedItem) ?? selectedHistoryItemID {
            selectedHistoryItemID = activeID
        }

        switch event.keyCode {
        case 123:
            if selectedHistoryItemID == nil {
                selectedHistoryItemID = store.items.first?.id
            }
            selectedHistoryColumn = .paste
            isKeyboardNavigatingHistory = true
            updateHistoryMenuRows()
            return nil
        case 124:
            if selectedHistoryItemID == nil {
                selectedHistoryItemID = store.items.first?.id
            }
            selectedHistoryColumn = .remove
            isKeyboardNavigatingHistory = true
            updateHistoryMenuRows()
            return nil
        case 125:
            moveHistorySelection(by: 1)
            return nil
        case 126:
            moveHistorySelection(by: -1)
            return nil
        case 36 where selectedHistoryColumn == .remove,
             76 where selectedHistoryColumn == .remove:
            removeSelectedHistoryItem()
            return nil
        case 36, 76:
            restoreSelectedHistoryItem()
            return nil
        case 18, 19, 20, 21, 22, 23, 25, 26, 28:
            activateNumberedHistoryItem(for: event)
            return nil
        default:
            return event
        }
    }

    private func moveHistorySelection(by offset: Int) {
        guard !store.items.isEmpty else { return }

        guard let currentIndex = selectedHistoryItemID
            .flatMap({ id in store.items.firstIndex(where: { $0.id == id }) }) else {
            let nextIndex = offset > 0 ? 0 : store.items.count - 1
            selectedHistoryItemID = store.items[nextIndex].id
            isKeyboardNavigatingHistory = true
            updateHistoryMenuRows()
            focusSelectedHistoryView()
            showPreview(for: store.items[nextIndex], near: view(for: store.items[nextIndex].id))
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), store.items.count - 1)
        selectedHistoryItemID = store.items[nextIndex].id
        isKeyboardNavigatingHistory = true
        updateHistoryMenuRows()
        focusSelectedHistoryView()
        showPreview(for: store.items[nextIndex], near: view(for: store.items[nextIndex].id))
    }

    private enum SelectionSource {
        case keyboard
        case mouse
    }

    private func selectHistoryItem(_ id: UUID, column: HistoryMenuColumn, source: SelectionSource) {
        if source == .mouse && isKeyboardNavigatingHistory {
            return
        }

        selectedHistoryItemID = id
        selectedHistoryColumn = column
        isKeyboardNavigatingHistory = source == .keyboard
        updateHistoryMenuRows()
        focusSelectedHistoryView()
    }

    private func resumeMouseSelection() {
        isKeyboardNavigatingHistory = false
    }

    private func restoreSelectedHistoryItem() {
        guard selectedHistoryColumn == .paste,
              let selectedHistoryItemID,
              let item = store.items.first(where: { $0.id == selectedHistoryItemID }) else {
            return
        }
        restore(item)
    }

    private func activateNumberedHistoryItem(for event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.first,
              let number = Int(String(character)),
              number > 0,
              number <= store.items.count else {
            return
        }
        restore(store.items[number - 1])
    }

    private func removeSelectedHistoryItem() {
        guard selectedHistoryColumn == .remove,
              let selectedHistoryItemID,
              let removedIndex = store.items.firstIndex(where: { $0.id == selectedHistoryItemID }) else {
            return
        }

        store.remove(id: selectedHistoryItemID)

        if store.items.isEmpty {
            self.selectedHistoryItemID = nil
            selectedHistoryColumn = .paste
        } else {
            let nextIndex = min(removedIndex, store.items.count - 1)
            self.selectedHistoryItemID = store.items[nextIndex].id
            selectedHistoryColumn = .remove
            isKeyboardNavigatingHistory = true
        }

        TextPreviewController.shared.hide()
        reopenMenuPreservingSelection()
    }

    private func removeHistoryItem(id: UUID) {
        selectedHistoryItemID = id
        selectedHistoryColumn = .remove
        isKeyboardNavigatingHistory = false
        removeSelectedHistoryItem()
    }

    private func reopenMenuPreservingSelection() {
        shouldPreserveSelectionOnOpen = true
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showStatusMenu()
        }
    }

    private func updateHistoryMenuRows() {
        for menuItem in menu.items {
            guard let uuid = historyItemID(for: menuItem),
                  let view = menuItem.view as? HistoryMenuItemView else {
                continue
            }

            view.updateSelection(
                isSelected: selectedHistoryItemID == uuid,
                selectedColumn: selectedHistoryColumn
            )
        }
    }

    private func focusSelectedHistoryView() {
        guard let selectedHistoryItemID,
              let view = view(for: selectedHistoryItemID) else {
            return
        }

        view.window?.makeFirstResponder(view)
    }

    private func view(for id: UUID) -> HistoryMenuItemView? {
        menu.items
            .first { historyItemID(for: $0) == id }?
            .view as? HistoryMenuItemView
    }

    private func historyItemID(for item: NSMenuItem?) -> UUID? {
        guard let id = item?.representedObject as? String else { return nil }
        return UUID(uuidString: id)
    }

    private func showPreview(for item: ClipboardHistoryItem, near view: NSView?) {
        guard item.kind == .text,
              let text = item.text,
              !text.isEmpty,
              let view,
              let window = view.window else {
            TextPreviewController.shared.hide()
            return
        }

        let viewFrame = view.convert(view.bounds, to: nil)
        TextPreviewController.shared.show(
            text: text,
            near: window.convertToScreen(viewFrame),
            on: menuScreen()
        )
    }

    private func restore(_ item: ClipboardHistoryItem) {
        menu.cancelTracking()
        TextPreviewController.shared.hide()
        clipboardMonitor.restore(item)
        PasteDispatcher.shared.pasteAfterMenuSelection()
        if !PasteDispatcher.shared.hasAccessibilityPermission {
            PasteDispatcher.shared.requestAccessibilityPermission()
        }
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

private final class HistoryMenuItemView: NSView {
    static let rowHeight: CGFloat = 42

    private static let rowWidth: CGFloat = 340
    private static let deleteColumnWidth: CGFloat = 28
    private static let iconSize: CGFloat = 18

    let itemID: UUID

    var onSelect: ((HistoryMenuColumn) -> Void)?
    var onActivate: (() -> Void)?
    var onRemove: (() -> Void)?
    var onPreview: (() -> Void)?
    var onMouseMoved: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?

    private let item: ClipboardHistoryItem
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var lastMouseLocation: NSPoint?
    private var isSelected: Bool
    private var selectedColumn: HistoryMenuColumn

    override var isFlipped: Bool { true }

    init(
        item: ClipboardHistoryItem,
        icon: NSImage?,
        subtitle: String,
        isSelected: Bool,
        selectedColumn: HistoryMenuColumn
    ) {
        self.item = item
        self.itemID = item.id
        self.isSelected = isSelected
        self.selectedColumn = selectedColumn

        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: Self.rowHeight))

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        titleField.stringValue = item.displayTitle
        titleField.font = .systemFont(ofSize: 14)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        addSubview(titleField)

        subtitleField.stringValue = subtitle
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1
        addSubview(subtitleField)

        updateLabelColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        let textStart = Self.deleteColumnWidth + 8 + Self.iconSize + 8
        let textWidth = bounds.width - textStart - Self.deleteColumnWidth - 12

        iconView.frame = NSRect(
            x: 8,
            y: 12,
            width: Self.iconSize,
            height: Self.iconSize
        )
        let titleX = 8 + Self.iconSize + 8
        titleField.frame = NSRect(x: titleX, y: 6, width: textWidth, height: 17)
        subtitleField.frame = NSRect(x: titleX, y: 23, width: textWidth, height: 14)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let xColumnRect = NSRect(x: bounds.width - Self.deleteColumnWidth, y: 0, width: Self.deleteColumnWidth, height: bounds.height)
        let pasteRect = NSRect(x: 0, y: 0, width: bounds.width - Self.deleteColumnWidth, height: bounds.height)

        if isSelected && selectedColumn == .paste {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: pasteRect.insetBy(dx: 3, dy: 3), xRadius: 5, yRadius: 5).fill()
        }

        if isSelected && selectedColumn == .remove {
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: xColumnRect.insetBy(dx: 4, dy: 6), xRadius: 5, yRadius: 5).fill()
        } else if isSelected {
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.width - Self.deleteColumnWidth, y: 7))
            path.line(to: NSPoint(x: bounds.width - Self.deleteColumnWidth, y: bounds.height - 7))
            path.stroke()
        }

        if isSelected {
            let xAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: selectedColumn == .remove ? NSColor.white : NSColor.secondaryLabelColor
            ]
            let xString = NSAttributedString(string: "×", attributes: xAttributes)
            let xSize = xString.size()
            xString.draw(at: NSPoint(
                x: bounds.width - Self.deleteColumnWidth + (Self.deleteColumnWidth - xSize.width) / 2,
                y: (bounds.height - xSize.height) / 2 - 1
            ))
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        noteMouseMovement(for: event)
        selectColumn(for: event)
        onPreview?()
    }

    override func mouseMoved(with event: NSEvent) {
        noteMouseMovement(for: event)
        selectColumn(for: event)
        onPreview?()
    }

    override func mouseExited(with event: NSEvent) {
        TextPreviewController.shared.hide()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseMoved?()
        let location = convert(event.locationInWindow, from: nil)
        if isSelected && location.x >= bounds.width - Self.deleteColumnWidth {
            onSelect?(.remove)
            onRemove?()
        } else {
            onSelect?(.paste)
            onActivate?()
        }
    }

    func updateSelection(isSelected: Bool, selectedColumn: HistoryMenuColumn) {
        self.isSelected = isSelected
        self.selectedColumn = selectedColumn
        updateLabelColors()
        needsDisplay = true
    }

    private func selectColumn(for event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onSelect?(isSelected && location.x >= bounds.width - Self.deleteColumnWidth ? .remove : .paste)
    }

    private func noteMouseMovement(for event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        defer { lastMouseLocation = location }

        guard let lastMouseLocation else {
            onMouseMoved?()
            return
        }

        if abs(location.x - lastMouseLocation.x) > 0.5 || abs(location.y - lastMouseLocation.y) > 0.5 {
            onMouseMoved?()
        }
    }

    private func updateLabelColors() {
        let pasteSelected = isSelected && selectedColumn == .paste
        titleField.textColor = pasteSelected ? .alternateSelectedControlTextColor : .labelColor
        subtitleField.textColor = pasteSelected ? .alternateSelectedControlTextColor.withAlphaComponent(0.78) : .secondaryLabelColor
        iconView.contentTintColor = pasteSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }
}
