//
//  LoadingCurtain.swift
//  Spot
//

import SwiftUI

/// The whole window while the open sequence's recording gets ready: a white ♮ on black, with progress as a line
/// along the bottom. When it's done, it closes up into the header, fading to the header's colour and the ♮
/// shrinking into the header's.
///
/// At launch it's there from the start. Opening a sequence later, the window fades quickly to black, the ♮ fades
/// in a little more slowly, then the progress runs, and it closes up the same way.
struct LoadingCurtain: View {
    @Environment(SequenceSession.self) private var session
    @Environment(UIState.self) private var ui

    /// Covering the window, or the size of the header (and looking just like it).
    @State private var isOpen = true
    /// Shown at all (once it has closed up, it fades out over the header, which it matches).
    @State private var isShown = true
    @State private var logoOpacity: Double = 1
    /// Progress only runs once the ♮ is in.
    @State private var isReady = true
    @State private var progress: Double = 0
    @State private var openedAt = Date()
    @State private var closing: DispatchWorkItem?
    /// The first showing, at launch: the IKKO logo goes below the ♮ (not when opening a sequence later).
    @State private var isLaunch = true
    @State private var ikkoOpacity: Double = 1

    private static let glyphSize: CGFloat = 120
    private static let headerGlyphSize: CGFloat = 38
    /// Long enough to see what's happening, even when there's nothing to load.
    private static let minimumTime = 0.9
    private static let closeDuration = 0.75
    private static let fadeToBlack = 0.15
    private static let logoFade = 0.4
    private static let ikkoSize: CGFloat = 110
    /// The IKKO logo fades out this long before the curtain starts closing up.
    private static let ikkoFade = 0.3

    var body: some View {
        GeometryReader { geometry in
            // Black while loading, turning to the header's colour as it closes up into it
            ZStack {
                (isOpen ? Color.black : Header.backgroundColor)
                // The font size itself animates (not a scaled-down large glyph), so it ends exactly as the header's
                Text("♮")
                    .modifier(AnimatableFontSize(size: isOpen ? LoadingCurtain.glyphSize : LoadingCurtain.headerGlyphSize))
                    .opacity(logoOpacity)
                    // At launch: the IKKO logo below it (an overlay, so the ♮ stays in the middle and closes up just
                    // the same), fading as it closes
                    .overlay(alignment: .bottom) {
                        if isLaunch {
                            Image("IkkoLogo")
                                .resizable()
                                .interpolation(.high)
                                .frame(width: LoadingCurtain.ikkoSize, height: LoadingCurtain.ikkoSize)
                                .offset(y: LoadingCurtain.ikkoSize + 8)
                                .opacity(ikkoOpacity)
                        }
                    }
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
                    .opacity(isOpen && isReady ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: isOpen)
            }
        }
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown && isOpen)
        .onAppear(perform: update)
        .onChange(of: session.isPreparingAudio) { update() }
        .onChange(of: session.audioProgress) { showProgress() }
    }

    private func showProgress() {
        guard isOpen, isReady else { return }
        withAnimation(.easeOut(duration: 0.25)) { progress = max(progress, session.audioProgress) }
    }

    private func update() {
        if session.isPreparingAudio {
            closing?.cancel()
            guard !isShown || !isOpen else { return }
            open()
        } else if isShown && isOpen {
            close()
        }
    }

    /// Opening a sequence: a quick fade to black over the window, then the ♮ fading in, then the progress.
    private func open() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            isLaunch = false
            isShown = false
            isOpen = true
            logoOpacity = 0
            isReady = false
            progress = 0
        }
        openedAt = Date()
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: LoadingCurtain.fadeToBlack)) { isShown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + LoadingCurtain.fadeToBlack) {
                withAnimation(.easeInOut(duration: LoadingCurtain.logoFade)) { logoOpacity = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + LoadingCurtain.logoFade) {
                    isReady = true
                    showProgress()
                    // It may have finished loading meanwhile
                    update()
                }
            }
        }
    }

    /// Done: fill the bar, wait out the minimum, then close up into the header and fade over it.
    private func close() {
        guard isReady else { return }   // still fading in; that finishes and comes back here
        withAnimation(.easeOut(duration: 0.3)) { progress = 1 }
        // Just long enough for the bar to fill (and to have been seen), then straight on
        let wait = max(LoadingCurtain.minimumTime - Date().timeIntervalSince(openedAt), 0.3)
        let work = DispatchWorkItem {
            // The IKKO logo (at launch) goes first, so only the ♮ moves
            let logoFade = isLaunch && ikkoOpacity > 0 ? LoadingCurtain.ikkoFade : 0
            if logoFade > 0 {
                withAnimation(.easeOut(duration: logoFade)) { ikkoOpacity = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + logoFade) {
                // Loading again meanwhile: stay open
                guard !session.isPreparingAudio else { return }
                closeUp()
            }
        }
        closing = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// Closes up into the header, then fades over it.
    private func closeUp() {
        // Eased in and out with no overshoot (a spring settles with a wobble at the end), then a fade over the
        // header underneath, which it now matches, rather than a sudden swap
        withAnimation(.timingCurve(0.65, 0, 0.3, 1, duration: LoadingCurtain.closeDuration)) { isOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + LoadingCurtain.closeDuration) {
            guard !isOpen else { return }
            withAnimation(.easeOut(duration: 0.25)) { isShown = false }
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
