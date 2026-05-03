import AppKit

final class ShortcutCaptureView: NSView {
    var onShortcutCaptured: ((HotKey) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var hotKey: HotKey
    private var isRecording = false

    init(hotKey: HotKey) {
        self.hotKey = hotKey
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 220),
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        updateLabel()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !event.isARepeat, !flags.isEmpty else {
            NSSound.beep()
            return
        }

        hotKey = HotKey.fromNSEvent(keyCode: event.keyCode, modifierFlags: event.modifierFlags.rawValue)
        isRecording = false
        updateLabel()
        onShortcutCaptured?(hotKey)
        window?.makeFirstResponder(nil)
    }

    func setHotKey(_ hotKey: HotKey) {
        self.hotKey = hotKey
        isRecording = false
        updateLabel()
    }

    private func updateLabel() {
        label.stringValue = isRecording ? "Press shortcut..." : hotKey.displayString
        layer?.backgroundColor = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor : NSColor.controlBackgroundColor.cgColor
    }
}
