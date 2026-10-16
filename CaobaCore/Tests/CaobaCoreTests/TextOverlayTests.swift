import Testing
import Foundation
import CoreGraphics
import CoreImage
import AVFoundation
@testable import CaobaCore

@Suite("Texto sobre el vídeo")
struct TextOverlayTests {
    let canvas = PixelSize(width: 640, height: 360)

    /// Cuenta píxeles con alfa en una zona (sobre la capa transparente).
    func opaquePixels(_ image: CGImage, in rect: CGRect) -> Int {
        guard let data = image.dataProvider?.data, let base = CFDataGetBytePtr(data) else { return 0 }
        let bpr = image.bytesPerRow
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where base[y * bpr + x * 4 + 3] > 40 { count += 1 }
        }
        return count
    }

    @Test("La capa de texto cae en la zona de la posición elegida y nada fuera")
    func anchors() {
        let style = TextStyle(fontName: nil, bold: true, sizePercent: 8, anchor: .bottomRight, backdrop: .none)
        let layer = TextRenderer.layer(lines: ["Boda de A y S"], style: style, canvas: canvas)!
        #expect(layer.width == 640 && layer.height == 360)
        // CGImage con origen arriba: abajo-derecha es la mitad inferior derecha.
        #expect(opaquePixels(layer, in: CGRect(x: 320, y: 180, width: 320, height: 180)) > 200)
        #expect(opaquePixels(layer, in: CGRect(x: 0, y: 0, width: 320, height: 180)) == 0)
        let top = TextRenderer.layer(lines: ["Arriba"], style: TextStyle(sizePercent: 8, anchor: .topLeft, backdrop: .none), canvas: canvas)!
        #expect(opaquePixels(top, in: CGRect(x: 0, y: 0, width: 320, height: 120)) > 200)
        #expect(opaquePixels(top, in: CGRect(x: 0, y: 240, width: 640, height: 120)) == 0)
    }

    @Test("La banda de fondo añade píxeles alrededor del texto y el texto vacío no genera capa")
    func bandAndEmpty() {
        let plain = TextRenderer.layer(lines: ["Pie"], style: TextStyle(sizePercent: 5, anchor: .center, backdrop: .none), canvas: canvas)!
        let band = TextRenderer.layer(lines: ["Pie"], style: TextStyle(sizePercent: 5, anchor: .center, backdrop: .band), canvas: canvas)!
        let all = CGRect(x: 0, y: 0, width: 640, height: 360)
        #expect(opaquePixels(band, in: all) > opaquePixels(plain, in: all) * 2)
        #expect(TextRenderer.layer(lines: ["", "  "], style: .caption, canvas: canvas) == nil)
    }

    @Test("La tarjeta de título tiene el fondo pedido y texto encima; dos líneas ocupan más alto que una")
    func card() throws {
        let one = try TextRenderer.card(lines: ["Título"], style: .title, background: CGColor(red: 0, green: 0, blue: 0, alpha: 1), canvas: canvas)
        let two = try TextRenderer.card(lines: ["Título", "Subtítulo"], style: .title, background: CGColor(red: 0, green: 0, blue: 0, alpha: 1), canvas: canvas)
        let corner = TestImages.pixel(one, x: 5, y: 5)
        #expect(corner.r < 10 && corner.g < 10 && corner.b < 10)
        func lit(_ img: CGImage) -> Int {
            var n = 0
            for y in stride(from: 0, to: 360, by: 3) { for x in stride(from: 0, to: 640, by: 3) where TestImages.pixel(img, x: x, y: y).r > 128 { n += 1 } }
            return n
        }
        #expect(lit(one) > 30)
        #expect(lit(two) > lit(one))
    }

    @Test("El título superpuesto entra y sale con su animación, respetando desfase y retardo")
    func overlayPhase() {
        var style = TextStyle.title
        style.animation = .fade; style.animationDuration = 1
        let overlay = TextOverlay(lines: ["Hola"], style: style, duration: 4)
        #expect(overlay.opacity(at: 0) == 0)
        #expect(abs(overlay.opacity(at: 0.5) - 0.5) < 1e-9)
        #expect(overlay.opacity(at: 2) == 1)
        #expect(abs(overlay.opacity(at: 3.5) - 0.5) < 1e-9)
        #expect(overlay.phase(at: 3.5)?.exiting == true)
        #expect(overlay.opacity(at: 5) == 0)
        // Con retardo de 1 s, a los 0,5 s aún no se ve; sin animación, se ve entero todo el tiempo.
        let delayed = TextOverlay(lines: ["Hola"], style: style, duration: 4, delay: 1)
        #expect(delayed.phase(at: 0.5) == nil)
        #expect(abs(delayed.opacity(at: 1.5) - 0.5) < 1e-9)
        style.animation = .none
        #expect(TextOverlay(lines: ["Hola"], style: style, duration: 4).opacity(at: 0.01) == 1)
        // Animación más larga que la mitad del texto: se acorta para que entrada y salida quepan.
        let short = TextPhase.at(1, total: 1, animation: .fade, duration: 5)
        #expect(short?.progress == 0 && short?.exiting == true)
    }

    @Test("La máquina de escribir dibuja menos y el deslizamiento mueve el bloque")
    func typewriterAndSlide() {
        var style = TextStyle(sizePercent: 8, anchor: .center, backdrop: .none)
        let full = TextRenderer.render(lines: ["Alex & Sofi"], style: style, canvas: canvas)!
        let half = TextRenderer.render(lines: ["Alex & Sofi"], style: style, canvas: canvas, visibleCharacters: 4)!
        let all = CGRect(x: 0, y: 0, width: 640, height: 360)
        #expect(full.characters == 11)
        #expect(opaquePixels(half.image, in: all) < opaquePixels(full.image, in: all) / 2)
        #expect(half.block == full.block)
        // Deslizar desde abajo a medio camino: el texto está más abajo que en su sitio.
        style.animation = .slideUp
        let ctx = CIContext()
        func centroidY(_ image: CIImage) -> Double {
            let cg = ctx.createCGImage(image, from: all)!
            var sum = 0.0, n = 0.0
            for y in stride(from: 0, to: 360, by: 2) { for x in stride(from: 0, to: 640, by: 2) where TestImages.pixel(cg, x: x, y: y).r > 100 { sum += Double(y); n += 1 } }
            return n > 0 ? sum / n : -1
        }
        let settled = centroidY(TextRenderer.animated(full, animation: .slideUp, phase: TextPhase(progress: 1, exiting: false), canvas: canvas))
        let moving = centroidY(TextRenderer.animated(full, animation: .slideUp, phase: TextPhase(progress: 0.5, exiting: false), canvas: canvas))
        #expect(moving > settled + 10)   // CGImage: la Y crece hacia abajo
        // Zoom a mitad: más pequeño (menos píxeles) que asentado.
        let zoomed = ctx.createCGImage(TextRenderer.animated(full, animation: .zoom, phase: TextPhase(progress: 0.5, exiting: false), canvas: canvas), from: all)!
        #expect(opaquePixels(zoomed, in: all) < opaquePixels(full.image, in: all))
    }

    @Test("Un vídeo con pie muestra texto en la zona del pie")
    func renderedCaption() async throws {
        let folder = try TestImages.makeTempFolder()
        let blue = folder.appendingPathComponent("blue.jpg")
        try TestImages.write(TestImages.solid(width: 640, height: 360, r: 0, g: 0, b: 1), to: blue, format: .jpeg)
        let output = folder.appendingPathComponent("c.mp4")
        var spec = SlideshowSpec(photos: [SlideshowPhoto(url: blue, duration: 2, transition: .cut, caption: "BOOK 01 · 1 de 1")],
                                 format: .landscape16x9, transition: false, output: output, preview: true)
        spec.captionStyle = TextStyle(sizePercent: 6, anchor: .bottomLeft, backdrop: .none)
        _ = try await SlideshowRenderer.generate(spec)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: output))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (frame, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
        // Abajo a la izquierda hay píxeles claros (texto blanco); arriba a la derecha sigue azul puro.
        var light = 0
        for y in stride(from: frame.height * 3 / 4, to: frame.height, by: 2) {
            for x in stride(from: 0, to: frame.width / 2, by: 2) where TestImages.pixel(frame, x: x, y: y).r > 150 { light += 1 }
        }
        #expect(light > 20)
        #expect(TestImages.isBlue(TestImages.pixel(frame, x: frame.width - 10, y: 10)))
    }
}
