//
//  LoadingCurtain.swift
//  Spot
//

import SwiftUI

/// The whole window while the open sequence's recording gets ready (at launch, or opening another): the ♮ on
/// the header's colour with a progress bar. When it's done, it closes up into the header (the ♮ shrinking into
/// the header's), and opens out from it again for the next.
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

    /// The ♮ is drawn large and scaled down into the header, so it stays sharp.
    private static let glyphSize: CGFloat = 120
    private static let headerGlyphSize: CGFloat = 38
    /// Long enough to see what's happening, even when there's nothing to load.
    private static let minimumTime = 0.9

    var body: some View {
        GeometryReader { geometry in
            let isOpen = phase == .open
            ZStack {
                Header.backgroundColor
                Text("♮")
                    .font(.system(size: LoadingCurtain.glyphSize))
                    .scaleEffect(isOpen ? 1 : LoadingCurtain.headerGlyphSize / LoadingCurtain.glyphSize)
                    .offset(y: isOpen ? -36 : 0)
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 280)
                    Text(label)
                        .font(.callout)
                        .opacity(0.85)
                }
                .offset(y: 70)
                .opacity(isOpen ? 1 : 0)
            }
            .foregroundColor(.white)
            // In macOS full screen there's no header to become: it closes up to nothing
            .frame(height: isOpen ? geometry.size.height : (ui.isWindowFullScreen ? 0 : Header.height))
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
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

    private var label: String {
        guard let name = session.sequence?.audio?.reference.fileName, session.isPreparingAudio else { return "Getting ready…" }
        return "Loading \(name)…"
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
                withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { phase = .open }
            }
        } else if phase == .open {
            // Fill the bar, wait out the minimum, then close up into the header
            withAnimation(.easeOut(duration: 0.3)) { progress = 1 }
            let wait = max(0, LoadingCurtain.minimumTime - Date().timeIntervalSince(openedAt)) + 0.35
            let work = DispatchWorkItem {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { phase = .closed }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if phase == .closed { phase = .hidden }
                }
            }
            closing = work
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
        }
    }
}
