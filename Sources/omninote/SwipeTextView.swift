import AppKit

/// NSTextView that reports a horizontal two-finger trackpad gesture as it happens, so the editor can move the
/// content with the finger. Vertical scrolling is passed through untouched; momentum tails are ignored.
final class SwipeTextView: NSTextView {
    var onDrag: ((_ offset: CGFloat) -> Void)?       // cumulative horizontal offset while the fingers are down
    var onDragEnd: ((_ offset: CGFloat) -> Void)?    // final offset when they lift
    private var accumulated: CGFloat = 0
    private var axis: Axis = .undecided

    private enum Axis { case undecided, horizontal, vertical }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase == [] else { super.scrollWheel(with: event); return }
        switch event.phase {
        case .began:
            accumulated = 0; axis = .undecided
        case .changed:
            if axis == .undecided {
                let dx = abs(event.scrollingDeltaX), dy = abs(event.scrollingDeltaY)
                if dx + dy > 6 { axis = dx > dy ? .horizontal : .vertical }  // lock the axis once the intent is clear
            }
            if axis == .horizontal {
                accumulated += event.scrollingDeltaX
                onDrag?(accumulated)
                return
            }
        case .ended, .cancelled:
            if axis == .horizontal { onDragEnd?(accumulated); accumulated = 0; axis = .undecided; return }
            axis = .undecided
        default: break
        }
        super.scrollWheel(with: event)
    }
}
