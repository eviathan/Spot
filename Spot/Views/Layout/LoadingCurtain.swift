//
//  LoadingCurtain.swift
//  Spot
//

import SwiftUI

/// The whole window while the open sequence's recording gets ready (at launch, or opening another): a white ♮ on
/// black, with progress as a line along the bottom. When it's done, it closes up into the header, fading to the
/// header's colour and the ♮ shrinking into the header's, and opens out from it again for the next.
struct LoadingCurtain: View {
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui

    private enum Phase {
        /// Covering the window.
        case open
        /// The size of the header (and looking just like it), over it.
        case closed
        /// Gone (the header underneath is the same).
        case hidden
    }

    @State private var phase: Phase = .open
    @State private var progress: Double = 0
    @State private var openedAt = Date()
    @State private var closing: DispatchWorkItem?

    private static let glyphSize: CGFloat = 120
    private static let headerGlyphSize: CGFloat = 38
    /// Long enough to see what's happening, even when there's nothing to load.
    private static let minimumTime = 0.9
    private static let closeDuration = 0.75

    var body: some View {
        GeometryReader { geometry in
            let isOpen = phase == .open
            // Black while loading, turning to the header's colour as it closes up into it
            ZStack {
                (isOpen ? Color.black : Header.backgroundColor)
                // The font size itself animates (not a scaled-down large glyph), so it ends exactly as the header's
                Text("♮")
                    .modifier(AnimatableFontSize(size: isOpen ? LoadingCurtain.glyphSize : LoadingCurtain.headerGlyphSize))
            }
            .foregroundColor(.white)
            .frame(height: isOpen ? geometry.size.height : (ui.isWindowFullScreen ? 0 : Header.height))
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            // Progress: a thin white line along the bottom of the window, the full width, gone as it closes
            .overlay(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.white)
                    .frame(width: geometry.size.width * progress, height: 3)
                    .opacity(isOpen ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: isOpen)
            }
        }
        .opacity(phase == .hidden ? 0 : 1)
        .allowsHitTesting(phase == .open)
        .onAppear(perform: update)
        .onChange(of: session.isPreparingAudio) { update() }
        .onChange(of: session.audioProgress) {
            guard phase == .open else { return }
            withAnimation(.easeOut(duration: 0.25)) { progress = max(progress, session.audioProgress) }
        }
    }

    private func update() {
        if session.isPreparingAudio {
            closing?.cancel()
            guard phase != .open else { return }
            // Open out from the header: start at its size (no change on screen), then grow
            progress = 0
            openedAt = Date()
            phase = .closed
            DispatchQueue.main.async {
                withAnimation(.timingCurve(0.65, 0, 0.3, 1, duration: 0.6)) { phase = .open }
            }
        } else if phase == .open {
            // Fill the bar, wait out the minimum, then close up into the header
            withAnimation(.easeOut(duration: 0.3)) { progress = 1 }
            let wait = max(0, LoadingCurtain.minimumTime - Date().timeIntervalSince(openedAt)) + 0.4
            let work = DispatchWorkItem {
                // Eased in and out with no overshoot (a spring settles with a wobble at the end), then a fade over
                // the header underneath, which it now matches, rather than a sudden swap
                withAnimation(.timingCurve(0.65, 0, 0.3, 1, duration: LoadingCurtain.closeDuration)) { phase = .closed }
                DispatchQueue.main.asyncAfter(deadline: .now() + LoadingCurtain.closeDuration) {
                    guard phase == .closed else { return }
                    withAnimation(.easeOut(duration: 0.25)) { phase = .hidden }
                }
            }
            closing = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
        }
    }
}

/// A system font whose size animates smoothly (a plain font change would just swap at the end).
private struct AnimatableFontSize: ViewModifier, Animatable {
    var size: CGFloat

    var animatableData: CGFloat {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size))
    }
}
