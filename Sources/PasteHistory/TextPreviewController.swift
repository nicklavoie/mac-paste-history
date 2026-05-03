import AppKit

final class TextPreviewController {
    static let shared = TextPreviewController()

    private let panel: NSPanel
    private let textView = NSTextView()
    private let scrollView = NSScrollView()

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true

        let container = NSVisualEffectView()
        container.material = .popover
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        scrollView.documentView = textView

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        panel.contentView = container
    }

    func show(text: String, from sourceView: NSView) {
        guard let window = sourceView.window,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        let sourceFrame = window.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
        let previewWidth: CGFloat = min(420, max(320, visibleFrame.width * 0.34))
        let measuredHeight = measuredTextHeight(for: text, width: previewWidth)
        let previewHeight = min(max(64, measuredHeight), min(520, visibleFrame.height))

        var x = sourceFrame.maxX + 8
        if x + previewWidth > visibleFrame.maxX {
            x = sourceFrame.minX - previewWidth - 8
        }
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - previewWidth)

        let centeredY = sourceFrame.midY - (previewHeight / 2)
        let y = min(max(centeredY, visibleFrame.minY), visibleFrame.maxY - previewHeight)

        textView.string = text
        textView.textContainer?.containerSize = NSSize(width: previewWidth - 20, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: previewWidth, height: max(measuredHeight, previewHeight))
        panel.setFrame(NSRect(x: x, y: y, width: previewWidth, height: previewHeight), display: true)
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func measuredTextHeight(for text: String, width: CGFloat) -> CGFloat {
        let textStorage = NSTextStorage(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        ])
        let textContainer = NSTextContainer(size: NSSize(width: width - 20, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height + 24
        return ceil(usedHeight)
    }
}
