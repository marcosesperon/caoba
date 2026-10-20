import Foundation
import AVFoundation
import Observation

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
