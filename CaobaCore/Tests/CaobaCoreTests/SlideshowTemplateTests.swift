import Testing
import Foundation
@testable import CaobaCore

@Suite("Plantillas del Slideshow")
struct SlideshowTemplateTests {
    /// Montaje de prueba con un poco de todo: lo general y lo que depende de las fotos.
    private func montage(folder: String = "a") -> SlideshowPreset {
        var p = SlideshowPreset()
        p.mode = "photos"
        p.videoFormat = "landscape16x9"
        p.durationPerPhoto = 5
        p.sortMode = "manual"
        p.fileOrder = ["\(folder)1.jpg", "\(folder)2.jpg"]
        p.excludedFiles = ["\(folder)3.jpg"]
        p.durations = ["\(folder)1.jpg": 8]
        p.transitionKind = "crossfade"
        p.transitionsByItem = ["cover": "cut", "\(folder)1.jpg": "slide"]
        p.cover = SlideshowPreset.ImageWithDuration(path: "/Plantillas/portada.png", duration: 4)
        p.musicTracks = [SlideshowPreset.MusicTrack(path: "/Música/navidad.m4a", mode: "auto")]
        var text = SlideshowPreset.TextSection()
        text.captionPattern = "{nombre}"
        text.captions = ["\(folder)1.jpg": "Pie a mano"]
        text.cards = [
            TextCard(text: "{sesion}", subtitle: "{fecha_sesion}", anchor: TextCard.startAnchor),
            TextCard(text: "En medio", anchor: "\(folder)2.jpg"),
            TextCard(text: "Fin", anchor: TextCard.endAnchor),
        ]
        p.text = text
        var kb = SlideshowPreset.KenBurnsSection()
        kb.intensity = "strong"
        kb.byFile = ["\(folder)1.jpg": "zoomIn"]
        p.kenBurns = kb
        var cs = SlideshowPreset.CollageSection()
        cs.gap = 20
        cs.sequence = ["grid-2"]
        cs.holdByRow = ["0": 5]
        p.collage = cs
        p.rhythmItems = ["\(folder)1.jpg"]
        return p
    }

    @Test("La plantilla se queda con lo general y quita lo de las fotos")
    func templated() {
        let (t, dropped) = montage().templated()
        #expect(dropped == 1)
        #expect(t.durationPerPhoto == 5 && t.videoFormat == "landscape16x9" && t.transitionKind == "crossfade")
        #expect(t.cover?.path == "/Plantillas/portada.png")
        #expect(t.musicTracks?.first?.path == "/Música/navidad.m4a")
        #expect(t.text?.captionPattern == "{nombre}")
        #expect(t.text?.cards?.map(\.text) == ["{sesion}", "Fin"])
        #expect(t.kenBurns?.intensity == "strong")
        #expect(t.collage?.gap == 20)
        // Fuera: lo que depende de las fotos.
        #expect(t.fileOrder == nil && t.excludedFiles == nil && t.durations == nil && t.sortMode == nil && t.rhythmItems == nil)
        #expect(t.text?.captions == nil)
        #expect(t.transitionsByItem == ["cover": "cut"])
        #expect(t.kenBurns?.byFile == nil)
        #expect(t.collage?.sequence == nil && t.collage?.holdByRow == nil)
    }

    @Test("Aplicar en una sesión: textos con su nombre y fecha, y lo de las fotos intacto")
    func applying() {
        let template = montage().templated().template
        var other = SlideshowPreset()
        other.fileOrder = ["b1.jpg", "b2.jpg"]
        other.durations = ["b2.jpg": 9]
        other.transitionsByItem = ["b2.jpg": "cut"]
        var text = SlideshowPreset.TextSection()
        text.captions = ["b1.jpg": "Mío"]
        text.cards = [TextCard(text: "Viejo título", anchor: TextCard.startAnchor), TextCard(text: "Delante de b2", anchor: "b2.jpg")]
        other.text = text

        let session = RenameSession(name: "Nombre de la sesión", dateText: "2026-11-15")
        let result = other.applying(template: template, session: session)
        // Lo general, de la plantilla.
        #expect(result.durationPerPhoto == 5 && result.cover?.path == "/Plantillas/portada.png")
        #expect(result.musicTracks?.count == 1 && result.kenBurns?.intensity == "strong")
        // Lo de las fotos, del montaje.
        #expect(result.fileOrder == ["b1.jpg", "b2.jpg"] && result.durations == ["b2.jpg": 9])
        #expect(result.text?.captions == ["b1.jpg": "Mío"])
        #expect(result.transitionsByItem == ["b2.jpg": "cut", "cover": "cut"])
        // Tarjetas: principio y final de la plantilla (con la sesión), la de en medio se queda.
        let cards = result.text?.cards ?? []
        #expect(cards.map(\.text) == ["Nombre de la sesión", "Delante de b2", "Fin"])
        #expect(cards.first?.subtitle == "2026-11-15")
        #expect(!template.text!.cards!.map(\.id).contains(cards[0].id)) // id nuevo
    }

    @Test("Una plantilla vacía devuelve lo general a sus valores de partida")
    func emptyTemplate() {
        let result = montage().applying(template: SlideshowPreset())
        #expect(result.cover == nil && result.musicTracks == nil && result.durationPerPhoto == nil)
        #expect(result.fileOrder == ["a1.jpg", "a2.jpg"])
        #expect(result.text?.cards?.map(\.text) == ["En medio"])
        #expect(result.kenBurns?.byFile == ["a1.jpg": "zoomIn"])
        #expect(result.collage?.sequence == ["grid-2"])
    }
}
