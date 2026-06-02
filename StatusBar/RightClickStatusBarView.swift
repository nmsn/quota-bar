import AppKit
import SwiftUI

class RightClickStatusBarView: NSView {
    private let hostingView: NSHostingView<StatusBarView>
    private let highlightView = HighlightOverlayView()
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    init(rootView: StatusBarView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.isHidden = true
        addSubview(highlightView)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        // 高亮 overlay 放在 hostingView 之下, 通过 SwiftUI 透明背景透出
        hostingView.layer?.backgroundColor = .clear

        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlightView.topAnchor.constraint(equalTo: topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor),

            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(rootView: StatusBarView) {
        hostingView.rootView = rootView
    }

    override func mouseDown(with event: NSEvent) {
        highlightView.isHidden = false
        if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        highlightView.isHidden = true
    }

    override func rightMouseDown(with event: NSEvent) {
        highlightView.isHidden = false
        onRightClick?()
    }

    override func rightMouseUp(with event: NSEvent) {
        highlightView.isHidden = true
    }
}

/// 自绘圆角矩形高亮 overlay, 模拟 macOS 状态栏按钮按压时的视觉反馈
private final class HighlightOverlayView: NSView {
    private let cornerRadius: CGFloat = 4
    private let highlightAlpha: CGFloat = 0.25
    private let edgeInset: CGFloat = 2

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: edgeInset, dy: edgeInset),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        NSColor.controlAccentColor.withAlphaComponent(highlightAlpha).setFill()
        path.fill()
    }
}
