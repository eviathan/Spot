//
//  OverlayScrollers.swift
//  Spot
//

import AppKit
import ObjectiveC

/// Scroll bars throughout Spot: hidden until you scroll, then fading in as a translucent white handle with no
/// track (macOS's overlay scrollers), whatever System Settings says (with a mouse attached it would otherwise show
/// permanent bars with a track). AppKit asks NSScroller which style to use, so that's answered for the whole app.
enum OverlayScrollers {
    static func install() {
        swap(class: NSScroller.self, classMethod: #selector(getter: NSScroller.preferredScrollerStyle),
             with: #selector(NSScroller.spot_preferredScrollerStyle))
        swap(class: NSScrollView.self, method: #selector(getter: NSScrollView.scrollerKnobStyle),
             with: #selector(NSScrollView.spot_scrollerKnobStyle))
        swap(class: NSScrollView.self, method: #selector(getter: NSScrollView.scrollerStyle),
             with: #selector(NSScrollView.spot_scrollerStyle))
    }

    private static func swap(class type: AnyClass, classMethod original: Selector, with replacement: Selector) {
        guard let a = class_getClassMethod(type, original), let b = class_getClassMethod(type, replacement) else { return }
        method_exchangeImplementations(a, b)
    }

    private static func swap(class type: AnyClass, method original: Selector, with replacement: Selector) {
        guard let a = class_getInstanceMethod(type, original), let b = class_getInstanceMethod(type, replacement) else { return }
        method_exchangeImplementations(a, b)
    }
}

extension NSScroller {
    @objc class func spot_preferredScrollerStyle() -> NSScroller.Style {
        .overlay
    }
}

extension NSScrollView {
    /// White, for the dark backgrounds everywhere in Spot.
    @objc func spot_scrollerKnobStyle() -> NSScroller.KnobStyle {
        .light
    }

    @objc func spot_scrollerStyle() -> NSScroller.Style {
        .overlay
    }
}
