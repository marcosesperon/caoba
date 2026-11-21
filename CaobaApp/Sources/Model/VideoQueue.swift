import Foundation
import Observation

/// Cola de «Generar vídeo» del Slideshow: solo un vídeo a la vez en toda la app (dos a la vez se
/// reparten el codificador y la GPU, y cada uno va más lento). La ventana que pulsa mientras otra
/// genera el suyo espera con «En cola…» y empieza sola al acabar, por orden de llegada.
@MainActor
@Observable
final class VideoQueue {
    /// Ventana cuyo vídeo se está generando.
    private(set) var running: AppState?
    /// Ventanas esperando, con lo que hay que lanzar cuando les toque.
    @ObservationIgnored private var waiting: [(window: AppState, start: () -> Void)] = []

    /// Pide turno para el vídeo de `window`: si no hay otro, empieza ya; si no, espera.
    func submit(_ window: AppState, start: @escaping () -> Void) {
        guard running != nil else {
            begin(window, start)
            return
        }
        waiting.append((window, start))
        window.jobRunner.onLeaveQueue = { [weak self, weak window] in
            guard let self, let window else { return }
            self.waiting.removeAll { $0.window === window }
        }
        window.jobRunner.enqueue(behind: Self.description(of: running))
    }

    /// El trabajo de `window` ha terminado (bien, mal o cancelado): si era el vídeo, pasa el siguiente.
    func finished(_ window: AppState) {
        guard running === window else { return }
        running = nil
        guard !waiting.isEmpty else { return }
        let next = waiting.removeFirst()
        next.window.jobRunner.leaveQueue()
        // Los que siguen esperando, ahora esperan a este.
        for other in waiting { other.window.jobRunner.enqueue(behind: Self.description(of: next.window)) }
        begin(next.window, next.start)
    }

    /// Lanza el vídeo de `window`. Si al final no arrancó (p. ej. faltaba el destino), no se
    /// queda con el turno: si no, la cola se quedaría esperando para siempre.
    private func begin(_ window: AppState, _ start: () -> Void) {
        running = window
        start()
        if !window.jobRunner.isRunning { finished(window) }
    }

    /// «el vídeo de Boda Marta y Javi» (o de la carpeta, sin sesión).
    private static func description(of window: AppState?) -> String {
        L("el vídeo de \(window?.workName ?? L("otra ventana"))")
    }
}
