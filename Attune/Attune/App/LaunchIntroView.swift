//
//  LaunchIntroView.swift
//  Attune
//
//  Plays the short branded intro immediately after the static iOS launch screen.
//

import AVFoundation
import SwiftUI

struct LaunchIntroView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let onFinished: () -> Void

    @State private var player = AVPlayer()
    @State private var fallbackTask: Task<Void, Never>?
    @State private var hasFinished = false

    var body: some View {
        LaunchIntroPlayerView(player: player, videoGravity: .resizeAspect)
        .background(Color.black)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: startPlayback)
        .onDisappear {
            fallbackTask?.cancel()
            player.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let finishedItem = notification.object as? AVPlayerItem,
                  finishedItem === player.currentItem else { return }
            finish()
        }
    }

    private func startPlayback() {
        guard !accessibilityReduceMotion else {
            finish()
            return
        }

        guard let videoURL = Bundle.main.url(forResource: "AttuneLaunchIntro", withExtension: "mp4") else {
            finish()
            return
        }

        let item = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
        player.play()

        // Never trap someone on the intro if playback or its completion notification fails.
        fallbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.25))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        fallbackTask?.cancel()
        player.pause()
        onFinished()
    }
}

private struct LaunchIntroPlayerView: UIViewRepresentable {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = videoGravity
    }
}

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
