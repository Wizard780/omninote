import AppKit

/// NSTextView that turns a horizontal two-finger trackpad swipe into one navigation step per gesture.
/// Vertical scrolling is passed through untouched.
final class SwipeTextView: NSTextView {
    var onSwipe: ((_ left: Bool) -> Void)?
    private var accumulated: CGFloat = 0
    private var fired = false
    private let threshold: CGFloat = 80

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase == [] else { super.scrollWheel(with: event); return }  // a flick's tail is never a second swipe
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        switch event.phase {
        case .began: accumulated = 0; fired = false
        case .changed where horizontal && !fired:
            accumulated += event.scrollingDeltaX
            if abs(accumulated) >= threshold {
                fired = true
                onSwipe?(accumulated < 0)  // finger moving left (negative deltaX) = "swipe left" = newer note
            }
            return
        case .ended, .cancelled: accumulated = 0
        default: break
        }
        if horizontal && event.phase != [] { return }  // swallow the rest of a horizontal gesture
        super.scrollWheel(with: event)
    }
}
