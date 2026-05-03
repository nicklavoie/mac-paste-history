import AppKit

final class TextHistoryMenuItemView: NSView {
    var onSelect: (() -> Void)?

    private let item: ClipboardHistoryItem
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    init(item: ClipboardHistoryItem, detail: String) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: 330, height: 46))

        iconView.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = item.displayTitle
        titleLabel.font = .systemFont(ofSize: 14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.stringValue = detail
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = NSStackView(views: [titleLabel, detailLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labelStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 330),
            heightAnchor.constraint(equalToConstant: 46),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            labelStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            labelStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard let text = item.text, !text.isEmpty else { return }
        TextPreviewController.shared.show(text: text, from: self)
    }

    override func mouseExited(with event: NSEvent) {
        TextPreviewController.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        TextPreviewController.shared.hide()
        onSelect?()
    }
}
