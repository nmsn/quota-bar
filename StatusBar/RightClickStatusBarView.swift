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
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        // 高亮 overlay 放在 hostingView 之上, 保证可见;
        // hitTest 返回 nil 让鼠标事件穿透到 RightClickStatusBarView 自身
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.isHidden = true
        addSubview(highlightView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),

            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlightView.topAnchor.constraint(equalTo: topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 添加 tracking area 以捕获 mouseEntered/mouseExited 事件
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
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

    override func mouseEntered(with event: NSEvent) {
        // No-op: hover 不改变高亮状态
    }

    override func mouseExited(with event: NSEvent) {
        highlightView.isHidden = true
    }

    override func mouseDragged(with event: NSEvent) {
        // 鼠标拖动超出 view 边界时隐藏高亮
        if !bounds.contains(convert(event.locationInWindow, from: nil)) {
            highlightView.isHidden = true
        }
    }
}

/// 自绘 pill / capsule 形状高亮 overlay, 模拟 macOS 状态栏按钮按压时的视觉反馈
private final class HighlightOverlayView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    // 高亮只用于视觉, 不接收鼠标事件 — 让事件穿透到下层的 hostingView / 父视图
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        // 适配明暗主题的白色半透明: 暗色模式 alpha 较小 (深色背景上白色更醒目),
        // 亮色模式 alpha 较大 (浅色背景上需要更多不透明度才有视觉对比)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let alpha: CGFloat = isDark ? 0.18 : 0.35
        NSColor.white.withAlphaComponent(alpha).setFill()

        // 铺满整个 slot, 让 highlight 成为一个明显的"容器";
        // 内容 (text + dot) 在 SwiftUI 内部已自带 padding, 会被自然居中
        // 半径 = min(宽, 高) / 2 → 左右两端是完整的半圆 (pill / capsule 形状)
        let radius = min(bounds.width, bounds.height) / 2
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: radius,
            yRadius: radius
        )
        path.fill()
    }
}
