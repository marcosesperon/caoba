import Testing
import Foundation
import CoreGraphics
@testable import CaobaCore

@Suite("CollageSlideshow")
struct CollageSlideshowTests {
    @Test("Duraciones: vacío, una por foto y hold al final")
    func durations() {
        let d = CollageSlideshow.durations(photos: 3, options: CollageSlideshow.Options(reveal: 1.5, hold: 3))
        #expect(d == [0.5, 1.5, 1.5, 4.5])
        // Un collage con "mantener" propio ignora el global.
        let own = CollageSlideshow.durations(photos: 2, options: CollageSlideshow.Options(reveal: 1, hold: 3), hold: 10)
        #expect(own == [0.5, 1, 11])
    }

    @Test("Render parcial y fotogramas en disco")
    func frames() async throws {
        let folder = try TestImages.makeTempFolder()
        let files = try (0..<2).map { try TestImages.makePhoto(in: folder, name: "p\($0).jpg", width: 200, height: 200) }
        let row = CollageRow(template: CollageTemplates.template(id: "diptico")!, files: files)
        let opts = CollageSlideshow.Options(reveal: 1, hold: 2, collage: CollageOptions(longestSide: 400, gap: 0, background: .black))
        let empty = try CollageRenderer.render(row, options: opts.collage, visibleCells: 0)
        let p = TestImages.pixel(empty, x: 100, y: 100)
        // Fondo "negro" (30,30,30) que tras la conversión de espacio de color queda en torno a 40.
        #expect(p.r < 60 && p.g < 60 && p.b < 60)
        let one = try CollageRenderer.render(row, options: opts.collage, visibleCells: 1)
        #expect(TestImages.isRed(TestImages.pixel(one, x: 50, y: 50)))
        let right = TestImages.pixel(one, x: 300, y: 100)
        #expect(right.r < 60) // la segunda celda aún vacía

        let dir = folder.appendingPathComponent("frames")
        let photos = try await CollageSlideshow.makePhotos(rows: [row], options: opts, directory: dir)
        #expect(photos.count == 3)
        #expect(photos.map(\.duration) == [0.5, 1, 3])
        #expect(ImageIOHelpers.displaySize(of: photos[0].url) == PixelSize(width: 400, height: 200))
    }
}

@Suite("SlideshowPreset")
struct SlideshowPresetTests {
    @Test("Lee un .caoba v1 de la app antigua")
    func legacy() throws {
        let folder = try TestImages.makeTempFolder()
        let json = """
        {"version":1,"slideshow":{"mode":"photos","sortMode":"manual","orientationFilter":"all","fileOrder":["b.jpg","a.jpg"],"excludedFiles":["c.jpg"],
         "videoFormat":"916_v","durationPerPhoto":5,"useTransition":true,"cover":{"path":"/x/cover.jpg","duration":3},
         "watermark":{"path":"/x/logo.png","position":"top_left","size":30,"opacity":0.8},"audio":{"fadeout":true,"normalize":false},
         "musicTracks":[{"path":"/x/a.mp3"},{"path":"/x/b.mp3","mode":"manual","startPhoto":4}],
         "kenBurns":{"intensity":"fast","easing":"ease_out","durationPct":70,"perPhoto":{"0":"zoom_in","2":"custom"},
           "points":{"2":{"startFx":0.2,"startFy":0.3,"startZoom":1.2,"endFx":0.8,"endFy":0.7,"endZoom":1.5,"fit":"cover","delayPct":10}}},
         "collage":{"templateMode":"sequential","revealDuration":1.5,"holdDuration":3,"bgColor":"white","gap":10,"borderRadius":0,"shadowIntensity":50,
           "focusPoints":{"0":[{"file":"a.jpg","fx":0.4,"fy":0.6,"imgAspect":1.5}]}}}}
        """
        try json.write(to: CaobaConfig.fileURL(in: folder), atomically: true, encoding: .utf8)
        let preset = SlideshowPreset.load(from: folder)!
        #expect(preset.videoFormat == "916_v" && preset.durationPerPhoto == 5 && preset.fileOrder == ["b.jpg", "a.jpg"])
        #expect(preset.watermark?.opacityPercent == 80)
        #expect(preset.musicTracks?[1].startPhoto == 4)
        #expect(preset.kenBurns?.perPhoto?["0"] == "zoom_in")
        let points = preset.kenBurns?.points?["2"]?.kenBurnsPoints
        #expect(points?.startFocus == CGPoint(x: 0.2, y: 0.3) && points?.endZoom == 1.5 && points?.delayPercent == 10)
        #expect(preset.collage?.focusPoints?["0"]?.first?.fx == 0.4)

        // Guardar de nuevo conserva lo leído y añade lo nuevo.
        var edited = preset
        edited.collage?.sequence = ["diptico", "1mas2"]
        try edited.save(in: folder)
        let again = SlideshowPreset.load(from: folder)!
        #expect(again.collage?.sequence == ["diptico", "1mas2"])
        #expect(again.musicTracks?.count == 2)
    }
}
