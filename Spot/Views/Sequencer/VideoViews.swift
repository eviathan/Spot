//
//  VideoViews.swift
//  Spot
//

import SwiftUI
import AVFoundation
import AppKit
import SpotCore

/// A video's frames along the lane, as in an editor's timeline: tiles the frame's shape, each the moment at its
/// middle (through the warp markers, so a stretched stretch shows fewer frames for longer). Tiles sit at fixed
/// places on the lane, so they scroll with it.
struct Filmstrip: View {
    let frames: VideoFrames
    /// Read so frames arriving redraw the strip.
    let version: Int
    let map: WarpMap
    /// The part of the lane drawn (lane x).
    let left: CGFloat
    let width: CGFloat
    let height: CGFloat
    let beatWidth: CGFloat
    let duration: Double

    var body: some View {
        Canvas { context, size in
            let tile = max(12, height * frames.aspectRatio)
            let first = Int(floor(left / tile)), last = Int(ceil((left + width) / tile))
            guard last >= first else { return }
            for index in first...last {
                let x = CGFloat(index) * tile
                let time = map.sourceTime(atBeat: Double((x + tile / 2) / beatWidth))
                guard time >= 0, time < duration else { continue }
                let next = map.sourceTime(atBeat: Double((x + tile * 1.5) / beatWidth))
                let rect = CGRect(x: x - left, y: 0, width: tile, height: size.height)
                if let image = frames.image(at: time, spacing: abs(next - time)) {
                    context.draw(Image(decorative: image, scale: 1), in: rect.insetBy(dx: 0.5, dy: 0))
                } else {
                    context.fill(Path(rect.insetBy(dx: 0.5, dy: 0)), with: .color(.white.opacity(0.06)))
                }
            }
            // A line under the strip, between it and the waveform
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(.black.opacity(0.5)))
        }
        .clipped()
    }
}

/// The video's picture, fitted in black.
struct VideoViewer: NSViewRepresentable {
    let player: AVPlayer

    final class PlayerView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}
