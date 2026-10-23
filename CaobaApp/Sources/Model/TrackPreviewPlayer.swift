import Foundation
import AVFoundation
import Observation
import CaobaCore

/// Reproductor para preescuchar una pista en su editor: suena el fichero tal cual (sin
/// fundidos ni normalización) solo entre Desde y Hasta, para oír dónde empieza y acaba.
@MainActor
@Observable
final class TrackPreviewPlayer {
    private(set) var isPlaying = false
    /// Por dónde va, en segundos de la canción.
    private(set) var position: Double = 0
    /// Tramo que se escucha (Desde y Hasta).
    private(set) var start: Double = 0
    private(set) var end: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    /// Nuevo tramo. Si cambia Desde, salta allí (y sigue sonando si sonaba); si solo cambia
    /// Hasta, sigue por donde iba y parará al llegar al nuevo final.
    func setRange(start newStart: Double, end newEnd: Double) {
        let startChanged = newStart != start
        start = max(0, newStart)
        end = max(start + 0.1, newEnd)
        if startChanged || position < start {
            seek(to: start)
        } else if position >= end {
            stop()
        }
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    /// Salta a un punto del tramo (barra de posición).
    func seek(to time: Double) {
        position = min(max(start, time), end)
        player?.currentTime = position
    }

    /// Para y vuelve a Desde (al llegar a Hasta, al cerrar el editor o al cambiar de pista).
    func stop() {
        pause()
        seek(to: start)
    }

    private func play() {
        guard let player else { return }
        // Si estaba al final del tramo, vuelve a empezar desde Desde.
        if position >= end - 0.05 { position = start }
        player.currentTime = position
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    /// Sigue la posición y para al llegar a Hasta.
    private func tick() {
        guard let player, isPlaying else { return }
        position = player.currentTime
        if position >= end || !player.isPlaying { stop() }
    }
}

/// Reproductor para escuchar un cruce entre pistas sin generar: monta la mezcla real del
/// vídeo (las mismas rampas de volumen, con `AudioMuxer.makeComposition`) y suena solo el
/// tramo pedido, de unos segundos antes a unos segundos después del cruce.
@MainActor
@Observable
final class MixPreviewPlayer {
    private(set) var isPlaying = false
    /// Por dónde va, en segundos del vídeo.
    private(set) var position: Double = 0
    /// Tramo que se escucha, en segundos del vídeo.
    private(set) var start: Double = 0
    private(set) var end: Double = 0
    /// Qué cruce se está escuchando (para marcar su botón); `nil` si ninguno.
    private(set) var current: String?
    private(set) var isLoading = false

    private var player: AVPlayer?
    private var timer: Timer?

    /// Monta la mezcla y suena de `from` a `to`. Si ya sonaba ese mismo cruce, lo pausa.
    func play(_ key: String, segments: [AudioSegment], totalDuration: Double, from: Double, to: Double) async {
        if current == key, isPlaying { pause(); return }
        if current == key, player != nil { resume(); return }
        stop()
        isLoading = true
        defer { isLoading = false }
        guard let (composition, mix) = try? await AudioMuxer.makeComposition(segments: segments, totalDuration: totalDuration) else { return }
        let item = AVPlayerItem(asset: composition)
        item.audioMix = mix
        start = max(0, from); end = max(start + 0.5, to)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        let player = AVPlayer(playerItem: item)
        await player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        self.player = player
        current = key
        position = start
        resume()
    }

    /// Para del todo (al cerrar el editor o al cambiar de pista).
    func stop() {
        pause()
        player = nil
        current = nil
    }

    private func resume() {
        guard let player else { return }
        // Si había llegado al final, vuelve al principio del tramo.
        if position >= end - 0.05 {
            position = start
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    /// Sigue la posición y se para al llegar al final del tramo.
    private func tick() {
        guard let player, isPlaying else { return }
        position = player.currentTime().seconds
        if position >= end - 0.02 || player.rate == 0 { pause() }
    }
}
