import Testing
import Foundation
@testable import CaobaCore

@Suite("Descargar tarjeta")
struct CardImportTests {
    private let fm = FileManager.default

    /// Crea un fichero con contenido y fecha dados.
    @discardableResult
    private func make(_ path: String, in root: URL, bytes: Int = 10, seed: UInt8 = 1, date: Date) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0) &+ seed }))
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }

    private let day1 = Date(timeIntervalSince1970: 1_763_100_000) // 14-11-2025
    private let day2 = Date(timeIntervalSince1970: 1_763_200_000) // 15-11-2025

    // MARK: Leer la tarjeta

    @Test("Lee DCIM y las carpetas de vídeo, con acompañantes, e ignora lo demás")
    func scan() throws {
        let card = try TestImages.makeTempFolder()
        try make("DCIM/100EOSR6/IMG_0001.CR3", in: card, date: day1)
        try make("DCIM/100EOSR6/IMG_0001.XMP", in: card, date: day1)
        try make("DCIM/100EOSR6/IMG_0002.JPG", in: card, date: day1)
        try make("DCIM/100EOSR6/._IMG_0002.JPG", in: card, date: day1)
        try make("DCIM/100EOSR6/MVI_0003.MP4", in: card, date: day1)
        try make("DCIM/100EOSR6/MVI_0003.THM", in: card, date: day1)
        try make("DCIM/CANONMSC/M0100.CTG", in: card, date: day1)
        try make("PRIVATE/M4ROOT/CLIP/C0001.MP4", in: card, date: day1)
        try make("MISC/CAMERA.JPG", in: card, date: day1)

        let all = CardScanner.scan(volume: card, groups: RecoveryFileGroup.photographerDefault)
        #expect(all.map(\.file.url.lastPathComponent) == ["IMG_0001.CR3", "IMG_0002.JPG", "MVI_0003.MP4", "C0001.MP4"])
        #expect(all[0].companions.map(\.url.lastPathComponent) == ["IMG_0001.XMP"])
        #expect(all[2].companions.map(\.url.lastPathComponent) == ["MVI_0003.THM"])
        #expect(CardScanner.scan(volume: card, groups: [.raw]).map(\.file.url.lastPathComponent) == ["IMG_0001.CR3"])
    }

    // MARK: Plan

    @Test("Todo junto o por fecha, y lo que ya está se salta")
    func planLayouts() throws {
        let card = try TestImages.makeTempFolder()
        let dest = try TestImages.makeTempFolder()
        try make("DCIM/100/IMG_0001.CR3", in: card, date: day1)
        try make("DCIM/100/IMG_0001.XMP", in: card, date: day1)
        try make("DCIM/100/IMG_0002.CR3", in: card, date: day2)
        let items = CardScanner.scan(volume: card, groups: [.raw])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let flat = CardImportPlan.make(items: items, destination: dest, layout: .flat)
        #expect(flat.tasks.map(\.destination.lastPathComponent) == ["IMG_0001.CR3", "IMG_0002.CR3"])
        #expect(flat.tasks[0].companions.map(\.destination.lastPathComponent) == ["IMG_0001.XMP"])
        #expect(flat.bytesToCopy == 30)

        let dated = CardImportPlan.make(items: items, destination: dest, layout: .byDate, calendar: utc)
        #expect(dated.tasks.map { $0.destination.path.replacingOccurrences(of: dest.path + "/", with: "") }
                == ["2025/11-14/IMG_0001.CR3", "2025/11-15/IMG_0002.CR3"])

        // Una ya descargada (mismo nombre, tamaño y fecha): se salta.
        try make("IMG_0001.CR3", in: dest, date: day1)
        let again = CardImportPlan.make(items: items, destination: dest, layout: .flat)
        #expect(again.alreadyThere == 1)
        #expect(again.tasks.map(\.destination.lastPathComponent) == ["IMG_0002.CR3"])
        #expect(again.totalItems == 2)
    }

    @Test("Dos tarjetas con los mismos nombres, por turnos y repetidas: sin duplicados ni sobrescribir")
    func twoCardsSameNames() async throws {
        let cardA = try TestImages.makeTempFolder()
        let cardB = try TestImages.makeTempFolder()
        let dest = try TestImages.makeTempFolder()
        try make("DCIM/100CANON/IMG_0001.JPG", in: cardA, bytes: 10, seed: 1, date: day1)
        try make("DCIM/100CANON/IMG_0001.JPG", in: cardB, bytes: 12, seed: 7, date: day2)

        func download(_ card: URL) async -> CardImportSummary {
            let plan = CardImportPlan.make(items: CardScanner.scan(volume: card, groups: [.jpeg]), destination: dest, layout: .flat)
            return await CardImporter.run(plan, cardVolume: card, control: CardImportControl())
        }
        #expect(await download(cardA).copied == 1)
        #expect(await download(cardB).copied == 1)
        // Repetir las dos (por ejemplo, al final de la sesión) no copia nada más.
        #expect(await download(cardA).alreadyThere == 1)
        let repeatB = await download(cardB)
        #expect(repeatB.alreadyThere == 1)
        #expect(repeatB.copied == 0)
        let names = try fm.contentsOfDirectory(atPath: dest.path).sorted()
        #expect(names == ["IMG_0001.JPG", "IMG_0001_2.JPG"])
        #expect(try Data(contentsOf: dest.appendingPathComponent("IMG_0001.JPG")) == Data(contentsOf: cardA.appendingPathComponent("DCIM/100CANON/IMG_0001.JPG")))
        #expect(try Data(contentsOf: dest.appendingPathComponent("IMG_0001_2.JPG")) == Data(contentsOf: cardB.appendingPathComponent("DCIM/100CANON/IMG_0001.JPG")))
    }

    // MARK: Copiar

    @Test("Copia comprobada: mismo contenido y fecha, sin temporales; reanuda tras un corte")
    func verifiedCopyAndResume() async throws {
        let card = try TestImages.makeTempFolder()
        let dest = try TestImages.makeTempFolder()
        try make("DCIM/100/IMG_0001.CR3", in: card, bytes: 9 << 20, date: day1)
        try make("DCIM/100/IMG_0001.XMP", in: card, date: day1)
        try make("DCIM/100/IMG_0002.CR3", in: card, bytes: 1000, date: day1)
        // Corte de una descarga anterior: la primera foto se quedó a medias.
        try make("IMG_0001.CR3.caoba-part", in: dest, bytes: 100, date: Date())

        let plan = CardImportPlan.make(items: CardScanner.scan(volume: card, groups: [.raw]), destination: dest, layout: .flat)
        #expect(plan.tasks.count == 2)
        let summary = await CardImporter.run(plan, cardVolume: card, control: CardImportControl())
        #expect(summary.copied == 2)
        #expect(summary.failures.isEmpty)
        #expect(summary.ending == .completed)
        #expect(try fm.contentsOfDirectory(atPath: dest.path).sorted() == ["IMG_0001.CR3", "IMG_0001.XMP", "IMG_0002.CR3"])
        let copy = dest.appendingPathComponent("IMG_0001.CR3")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: card.appendingPathComponent("DCIM/100/IMG_0001.CR3")))
        let date = try copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(abs(date!.timeIntervalSince(day1)) < 1)
    }

    @Test("Sin sitio, pausa y avisa; al seguir, termina")
    func pausesWhenFull() async throws {
        let card = try TestImages.makeTempFolder()
        let dest = try TestImages.makeTempFolder()
        try make("DCIM/100/A.JPG", in: card, date: day1)
        try make("DCIM/100/B.JPG", in: card, date: day1)
        let plan = CardImportPlan.make(items: CardScanner.scan(volume: card, groups: [.jpeg]), destination: dest, layout: .flat)
        let control = CardImportControl()
        // El disco «se llena» tras la primera foto y «se libera» al avisar.
        let space = SpaceStub()
        let summary = await CardImporter.run(plan, cardVolume: card, control: control,
                                             freeSpace: { _ in space.free },
                                             onNeedsSpace: { _ in
                                                 space.release()
                                                 control.resume()
                                             })
        #expect(space.asked)
        #expect(summary.copied == 2)
    }

    @Test("Cancelar para entre fotos y no deja nada a medias")
    func cancels() async throws {
        let card = try TestImages.makeTempFolder()
        let dest = try TestImages.makeTempFolder()
        for i in 1...3 { try make("DCIM/100/IMG_000\(i).JPG", in: card, date: day1) }
        let plan = CardImportPlan.make(items: CardScanner.scan(volume: card, groups: [.jpeg]), destination: dest, layout: .flat)
        let control = CardImportControl()
        let summary = await CardImporter.run(plan, cardVolume: card, control: control, progress: { state in
            if state.filesDone == 1 { control.cancel() }
        })
        #expect(summary.ending == .cancelled)
        #expect(summary.copied == 1)
        #expect(try fm.contentsOfDirectory(atPath: dest.path) == ["IMG_0001.JPG"])
    }
}

// MARK: Sesiones

extension CardImportTests {
    /// Una foto de mentira (no hace falta fichero) a esa hora.
    private func item(_ name: String, _ date: Date) -> CardItem {
        CardItem(file: CardFile(url: URL(fileURLWithPath: "/tarjeta/DCIM/100/" + name), size: 100, date: date), group: .jpeg)
    }

    @Test("Sesiones por huecos: el límite, varias el mismo día, la que cruza medianoche y por días")
    func sessions() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let base = Date(timeIntervalSince1970: 1_763_100_000) // 14-11-2025 06:00 UTC
        let h: TimeInterval = 3_600
        let items = [
            item("A1.JPG", base),                    // mañana
            item("A2.JPG", base + 1 * h),
            item("B1.JPG", base + 5 * h + 1),        // tarde: más de 4 h después
            item("B2.JPG", base + 9 * h + 1),        // justo 4 h: sigue en la misma
            item("C1.JPG", base + 17 * h),           // 23:00
            item("C2.JPG", base + 19 * h),           // 01:00 del día siguiente: sigue
        ]
        let fourHours = CardSessions.group(items, gap: .fourHours, calendar: utc)
        // De la más reciente a la más antigua.
        #expect(fourHours.map { $0.items.map(\.file.url.lastPathComponent) } == [["C1.JPG", "C2.JPG"], ["B1.JPG", "B2.JPG"], ["A1.JPG", "A2.JPG"]])
        #expect(fourHours[2].totalSize == 200)

        #expect(CardSessions.group(items, gap: .oneHour, calendar: utc).count == 5)
        #expect(CardSessions.group(items, gap: .eightHours, calendar: utc).count == 1)
        // Por días: la de medianoche se parte en dos.
        let byDay = CardSessions.group(items, gap: .byDay, calendar: utc)
        #expect(byDay.map { $0.items.map(\.file.url.lastPathComponent) } == [["C2.JPG"], ["A1.JPG", "A2.JPG", "B1.JPG", "B2.JPG", "C1.JPG"]])
        #expect(CardSessions.group([], gap: .fourHours).isEmpty)
    }

    @Test("Muestra repartida para la tira: primera, del medio y última")
    func sessionSample() {
        let base = Date(timeIntervalSince1970: 1_763_100_000)
        let many = CardSession(items: (0..<100).map { item(String(format: "IMG_%04d.JPG", $0), base + Double($0)) })
        #expect(many.sample(6).map(\.file.url.lastPathComponent) == ["IMG_0000.JPG", "IMG_0020.JPG", "IMG_0040.JPG", "IMG_0059.JPG", "IMG_0079.JPG", "IMG_0099.JPG"])
        let few = CardSession(items: (0..<3).map { item("F\($0).JPG", base + Double($0)) })
        #expect(few.sample(6).count == 3)
    }
}

/// Espacio libre de mentira: hay sitio para la primera foto, luego no, hasta que se libera al avisar.
private final class SpaceStub: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var freed = false

    var free: Int64 {
        lock.withLock {
            calls += 1
            return calls == 1 || freed ? 10_000_000_000 : 0
        }
    }
    var asked: Bool { lock.withLock { freed } }
    func release() { lock.withLock { freed = true } }
}
