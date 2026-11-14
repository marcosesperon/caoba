import Testing
import Foundation
@testable import CaobaCore

@Suite("Recuperar fotos")
struct RecoveryTests {

    // MARK: Orden de PhotoRec

    @Test("Por defecto: fotos y vídeos de cámara, solo espacio libre, log en la carpeta de salida")
    func defaultCommand() throws {
        let out = URL(fileURLWithPath: "/tmp/Mi recuperación")
        let args = try PhotoRecCommand.arguments(for: PhotoRecOptions(device: "/dev/rdisk4"), outputFolder: out)
        #expect(args == [
            "/log", "/logname", "/tmp/Mi recuperación/photorec.log",
            "/d", "/tmp/Mi recuperación/recup_dir",
            "/cmd", "/dev/rdisk4",
            "fileopt,everything,disable,jpg,enable,tif,enable,crw,enable,raf,enable,orf,enable,rw2,enable,mrw,enable,"
                + "x3f,enable,raw,enable,mov,enable,m2ts,enable,ts,enable,riff,enable,mpg,enable,mkv,enable,mxf,enable,"
                + "mlv,enable,r3d,enable,dv,enable,freespace,search",
        ])
    }

    @Test("ext2/3/4, toda la tarjeta y solo JPG")
    func extWholeDiskJpeg() {
        let options = PhotoRecOptions(device: "/dev/rdisk5", fileSystem: .ext, scope: .wholeDisk, groups: [.jpeg])
        #expect(PhotoRecCommand.script(for: options) == "options,mode_ext2,fileopt,everything,disable,jpg,enable,wholespace,search")
    }

    @Test("HEIC y RAW comparten la familia mov: sale una sola vez")
    func familiesWithoutRepeats() {
        #expect(PhotoRecCommand.families(for: [.heic, .raw]) == ["tif", "crw", "raf", "orf", "rw2", "mrw", "x3f", "raw", "mov"])
        #expect(PhotoRecCommand.families(for: [.heic]) == ["mov"])
    }

    @Test("«Otros archivos» activa todo lo que conoce PhotoRec")
    func otherFiles() {
        let options = PhotoRecOptions(device: "/dev/rdisk4", groups: [], includeOtherFiles: true)
        #expect(PhotoRecCommand.script(for: options) == "fileopt,everything,enable,freespace,search")
    }

    @Test("Sin nada que buscar o sin dispositivo, no se lanza")
    func invalidOptions() {
        let out = URL(fileURLWithPath: "/tmp/x")
        #expect(throws: CaobaError.noFiles) {
            try PhotoRecCommand.arguments(for: PhotoRecOptions(device: "/dev/rdisk4", groups: []), outputFolder: out)
        }
        #expect(throws: CaobaError.invalidParameters("device")) {
            try PhotoRecCommand.arguments(for: PhotoRecOptions(device: ""), outputFolder: out)
        }
    }

    /// Familias de PhotoRec 7.2 (extensión principal de cada `file_hint_t` en `src/file_*.c`)
    /// que usa CAOBA. Un nombre que no existe corta `fileopt` y PhotoRec da «Syntax error».
    @Test("Todas las familias usadas existen en PhotoRec 7.2")
    func familiesExist() {
        let known: Set<String> = ["jpg", "tif", "crw", "raf", "orf", "rw2", "mrw", "x3f", "raw", "mov", "m2ts", "ts",
                                  "riff", "mpg", "mkv", "mxf", "mlv", "r3d", "dv"]
        #expect(Set(PhotoRecCommand.families(for: Set(RecoveryFileGroup.allCases))).isSubset(of: known))
    }

    /// Prueba de verdad con el PhotoRec compilado (si está): una «tarjeta» en bruto sin
    /// sistema de archivos con un JPG dentro. Comprueba que la orden se entiende entera.
    @Test("PhotoRec real recupera un JPG de una imagen en bruto",
          .enabled(if: FileManager.default.isExecutableFile(atPath: RecoveryTests.photoRecPath.path)))
    func realPhotoRec() throws {
        let folder = try TestImages.makeTempFolder()
        let photo = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 300, height: 200, date: "2024:05:31 14:22:10")
        // 1 MB de ceros con la foto a partir del sector 64.
        var image = Data(count: 1 << 20)
        let jpeg = try Data(contentsOf: photo)
        image.replaceSubrange(32_768..<(32_768 + jpeg.count), with: jpeg)
        let disk = folder.appendingPathComponent("tarjeta.img")
        try image.write(to: disk)
        let out = folder.appendingPathComponent("salida")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = Self.photoRecPath
        process.arguments = try PhotoRecCommand.arguments(
            for: PhotoRecOptions(device: disk.path, scope: .wholeDisk), outputFolder: out)
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let log = try String(contentsOf: out.appendingPathComponent(PhotoRecCommand.logFileName), encoding: .utf8)
        let report = PhotoRecReport.parse(log: log)
        #expect(report.succeeded)
        #expect(report.recoveredByFamily["jpg"] == 1)
        let files = RecoveredFiles.list(in: out)
        #expect(files.count == 1)
        #expect(try Data(contentsOf: files[0]) == jpeg)
    }

    static let photoRecPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("CaobaApp/Vendor/photorec/photorec")

    // MARK: authopen y lanzador

    /// Una «tarjeta» en bruto de 1 MB con un JPG dentro, y el JPG.
    private func rawCard(in folder: URL, name: String = "tarjeta.img") throws -> (disk: URL, jpeg: Data) {
        let photo = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 300, height: 200)
        var image = Data(count: 1 << 20)
        let jpeg = try Data(contentsOf: photo)
        image.replaceSubrange(32_768..<(32_768 + jpeg.count), with: jpeg)
        let disk = folder.appendingPathComponent(name)
        try image.write(to: disk)
        return (disk, jpeg)
    }

    @Test("authopen devuelve el descriptor de un fichero (sin contraseña si el usuario ya puede leerlo)")
    func authOpenReceivesDescriptor() throws {
        let folder = try TestImages.makeTempFolder()
        let file = folder.appendingPathComponent("con espacio y 'apóstrofo'.bin")
        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        let handle = try AuthOpen.openReadOnly(file.path)
        #expect(try handle.readToEnd() == bytes)
        // Solo lectura: escribir falla.
        #expect(throws: (any Error).self) { try handle.write(contentsOf: Data([1])) }
    }

    @Test("authopen sin el fichero falla con su mensaje")
    func authOpenMissing() {
        #expect(throws: AuthOpen.Failure.self) { try AuthOpen.openReadOnly("/no/existe/tarjeta.img") }
    }

    @Test("PhotoRec lee la tarjeta por el descriptor (/dev/fd/0) y recupera",
          .enabled(if: FileManager.default.isExecutableFile(atPath: RecoveryTests.photoRecPath.path)))
    func launcherRecovers() async throws {
        let folder = try TestImages.makeTempFolder()
        let card = try rawCard(in: folder, name: "tarjeta con espacio.img")
        let out = folder.appendingPathComponent("salida")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let device = try AuthOpen.openReadOnly(card.disk.path)
        // Como una tarjeta de verdad, que es de root: ya abierta, el usuario no puede abrirla por la ruta.
        // Sin el parche de `/dev/fd` (Tools/photorec-fd.patch), PhotoRec daría «Permission denied».
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: card.disk.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: card.disk.path) }
        let args = try PhotoRecCommand.arguments(for: PhotoRecOptions(device: card.disk.path, scope: .wholeDisk), outputFolder: out)

        let exit = try await PhotoRecLauncher().run(photoRec: Self.photoRecPath, arguments: args, devicePath: card.disk.path,
                                                    device: device, outputFolder: out)
        #expect(exit == PhotoRecLauncher.Exit(status: 0, wasTerminated: false))
        let log = try String(contentsOf: out.appendingPathComponent(PhotoRecCommand.logFileName), encoding: .utf8)
        #expect(log.contains("/cmd /dev/fd/0"))
        #expect(PhotoRecReport.parse(log: log).succeeded)
        let files = RecoveredFiles.list(in: out)
        #expect(files.count == 1)
        #expect(try Data(contentsOf: files[0]) == card.jpeg)
    }

    @Test("Pausar detiene PhotoRec y cancelar en pausa lo para igual",
          .enabled(if: FileManager.default.isExecutableFile(atPath: RecoveryTests.photoRecPath.path)))
    func launcherPauses() async throws {
        let folder = try TestImages.makeTempFolder()
        let big = folder.appendingPathComponent("grande.img")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 8 << 30)
        try handle.close()
        defer { try? FileManager.default.removeItem(at: big) }
        let out = folder.appendingPathComponent("salida")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let args = try PhotoRecCommand.arguments(for: PhotoRecOptions(device: big.path, scope: .wholeDisk), outputFolder: out)

        let launcher = PhotoRecLauncher()
        let state = Task { () -> String in
            try await Task.sleep(for: .seconds(1))
            launcher.pause()
            try await Task.sleep(for: .milliseconds(500))
            let state = Self.processState(launcher.processIdentifier)
            launcher.terminate()
            return state
        }
        let start = Date()
        let exit = try await launcher.run(photoRec: Self.photoRecPath, arguments: args, devicePath: big.path,
                                          device: try AuthOpen.openReadOnly(big.path), outputFolder: out)
        // `T` = detenido en `ps`.
        #expect(try await state.value.hasPrefix("T"))
        #expect(exit.wasTerminated)
        #expect(Date().timeIntervalSince(start) < 10)
    }

    /// Estado de un proceso según `ps` (`R`, `S`, `T`…).
    static func processState(_ pid: Int32) -> String {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "state=", "-p", String(pid)]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try? ps.run()
        ps.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("Cancelar para PhotoRec a mitad",
          .enabled(if: FileManager.default.isExecutableFile(atPath: RecoveryTests.photoRecPath.path)))
    func launcherCancels() async throws {
        let folder = try TestImages.makeTempFolder()
        // 8 GB dispersos (no ocupan disco): no le da tiempo a acabar.
        let big = folder.appendingPathComponent("grande.img")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: 8 << 30)
        try handle.close()
        defer { try? FileManager.default.removeItem(at: big) }
        let out = folder.appendingPathComponent("salida")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let args = try PhotoRecCommand.arguments(for: PhotoRecOptions(device: big.path, scope: .wholeDisk), outputFolder: out)

        let launcher = PhotoRecLauncher()
        let start = Date()
        Task { try await Task.sleep(for: .seconds(1)); launcher.terminate() }
        let exit = try await launcher.run(photoRec: Self.photoRecPath, arguments: args, devicePath: big.path,
                                          device: try AuthOpen.openReadOnly(big.path), outputFolder: out)
        #expect(exit.wasTerminated)
        #expect(Date().timeIntervalSince(start) < 10)
        let log = (try? String(contentsOf: out.appendingPathComponent(PhotoRecCommand.logFileName), encoding: .utf8)) ?? ""
        #expect(!PhotoRecReport.parse(log: log).succeeded)
    }

    // MARK: Log de PhotoRec

    @Test("Log de una recuperación que va bien")
    func parseSuccess() {
        let log = """
        Pass 1 (blocksize=512) STATUS_EXT2_OFF
        out1/recup_dir.1/f0002051.jpg\t 2052-20302
        out1/recup_dir.1/f0020569.heic\t 20570-71907
        Elapsed time 0h00m00s
        Pass 1 +2 files
        jpg: 1/1 recovered
        mov: 1/1 recovered
        Total: 2 files found

        59162 sectors contain unknown data, 0 invalid files found and rejected.
        PhotoRec exited normally.
        """
        let report = PhotoRecReport.parse(log: log)
        #expect(report.succeeded)
        #expect(report.recoveredByFamily == ["jpg": 1, "mov": 1])
        #expect(report.total == 2)
    }

    @Test("Sale «normalmente» aunque no pudo escribir: cuenta como fallo")
    func parseWriteFailures() {
        let missing = PhotoRecReport.parse(log: """
            Cannot create file out2/recup_dir.1/f0002051.jpg: No such file or directory
            PhotoRec has been stopped
            Total: 0 files found
            PhotoRec exited normally.
            """)
        #expect(!missing.succeeded)
        #expect(missing.problems == [.destinationMissing])
        #expect(PhotoRecReport.parse(log: "Cannot write to file a/f1.jpg: No space left on device").problems == [.destinationFull])
        #expect(PhotoRecReport.parse(log: "Cannot create file a/f1.jpg: Permission denied").problems == [.destinationNotWritable])
    }

    @Test("Errores al abrir el disco, ext que no lo es y parada")
    func parseOtherProblems() {
        let open = PhotoRecReport.parse(log: "", output: "\nUnable to open file or device /dev/rdisk9: Resource busy\n")
        #expect(open.problems == [.cannotOpenDevice])
        #expect(!open.finishedNormally)
        #expect(PhotoRecReport.parse(log: "Not a valid ext2/ext3/ext4 filesystem").problems == [.notExtFileSystem])
        #expect(PhotoRecReport.parse(log: "SIGTERM detected! PhotoRec has been killed.").problems == [.stopped])
        #expect(PhotoRecReport.parse(log: "Syntax error in command line: foo").problems == [.other("Syntax error in command line: foo")])
    }

    // MARK: Ficheros recuperados

    @Test("Lista lo recuperado en orden, sin report.xml ni miniaturas, y lo cuenta por grupo")
    func recoveredFiles() throws {
        let out = try TestImages.makeTempFolder()
        let fm = FileManager.default
        for (dir, names) in [("recup_dir.2", ["f0000900.mp4"]),
                             ("recup_dir.1", ["f0000010.jpg", "t0000010.jpg", "f0000020_IMG_1.CR2", "f0000030.heic",
                                              "f0000040.pdf", "report.xml"]),
                             ("otra", ["f0000001.jpg"])] {
            let folder = out.appendingPathComponent(dir)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in names { fm.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1])) }
        }
        let files = RecoveredFiles.list(in: out)
        #expect(files.map { $0.deletingLastPathComponent().lastPathComponent + "/" + $0.lastPathComponent } == [
            "recup_dir.1/f0000010.jpg", "recup_dir.1/f0000020_IMG_1.CR2", "recup_dir.1/f0000030.heic",
            "recup_dir.1/f0000040.pdf", "recup_dir.2/f0000900.mp4",
        ])
        let counts = RecoveredFiles.count(files)
        #expect(counts.byGroup == [.jpeg: 1, .raw: 1, .heic: 1, .video: 1])
        #expect(counts.other == 1)
        #expect(counts.total == 5)
    }

    @Test("Bloques: por carpeta, sin lo que se está escribiendo; borrar ficheros con su miniatura y bloques enteros")
    func recoveredBlocks() throws {
        let out = try TestImages.makeTempFolder()
        let fm = FileManager.default
        for (dir, names) in [("recup_dir.1", ["f0000010.jpg", "t0000010.jpg", "f0000020.cr3"]),
                             ("recup_dir.3", ["f0000900.mp4", "f0000950.jpg"])] {
            let folder = out.appendingPathComponent(dir)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in names { fm.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1])) }
        }
        // El último JPG «se está escribiendo»: modificado hace un segundo.
        let writing = out.appendingPathComponent("recup_dir.3/f0000950.jpg")
        let now = Date()
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-1)], ofItemAtPath: writing.path)
        for name in ["recup_dir.1/f0000010.jpg", "recup_dir.1/f0000020.cr3", "recup_dir.3/f0000900.mp4"] {
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: out.appendingPathComponent(name).path)
        }

        let all = RecoveredFiles.blocks(in: out)
        #expect(all.map(\.number) == [1, 3])
        #expect(all.map { $0.files.map(\.lastPathComponent) } == [["f0000010.jpg", "f0000020.cr3"], ["f0000900.mp4", "f0000950.jpg"]])
        let settled = RecoveredFiles.blocks(in: out, settledFor: 3, now: now)
        #expect(settled[1].files.map(\.lastPathComponent) == ["f0000900.mp4"])

        // Borrar un JPG se lleva su miniatura; lo que ya no existe no es un fallo.
        let jpg = out.appendingPathComponent("recup_dir.1/f0000010.jpg")
        let result = RecoveredFiles.delete([jpg, out.appendingPathComponent("recup_dir.1/no-existe.jpg")])
        #expect(result.deleted == 1)
        #expect(result.failures.isEmpty)
        #expect(!fm.fileExists(atPath: out.appendingPathComponent("recup_dir.1/t0000010.jpg").path))
        #expect(fm.fileExists(atPath: out.appendingPathComponent("recup_dir.1/f0000020.cr3").path))

        // Borrar un bloque entero.
        #expect(try RecoveredFiles.deleteBlock(all[1]) == 2)
        #expect(RecoveredFiles.blocks(in: out).map(\.number) == [1])
    }

    // MARK: Fecha de captura

    @Test("Fecha EXIF de la foto; sin EXIF no hay fecha aunque el fichero tenga una")
    func photoDates() async throws {
        let folder = try TestImages.makeTempFolder()
        let dated = try TestImages.makePhoto(in: folder, name: "a.jpg", date: "2024:05:31 14:22:10")
        let undated = try TestImages.makePhoto(in: folder, name: "b.heic")
        #expect(await CaptureDateReader.captureDate(of: dated) == ExifDate.parse("2024:05:31 14:22:10"))
        #expect(await CaptureDateReader.captureDate(of: undated) == nil)
    }

    @Test("Fecha de creación de un vídeo")
    func videoDate() async throws {
        let folder = try TestImages.makeTempFolder()
        let photo = try TestImages.makePhoto(in: folder, name: "a.jpg", width: 640, height: 360)
        let video = folder.appendingPathComponent("v.mp4")
        // El Slideshow pone como fecha de creación el momento de exportar.
        try await SlideshowRenderer.generate(SlideshowSpec(photos: [SlideshowPhoto(url: photo, duration: 0.3)],
                                                           format: .landscape16x9, transition: false, output: video, preview: true))
        let date = try #require(await CaptureDateReader.captureDate(of: video))
        #expect(abs(date.timeIntervalSinceNow) < 120)
    }

    // MARK: Organizador

    @Test("Ruta por fecha y para lo que no la tiene")
    func relativePaths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let date = DateComponents(calendar: calendar, year: 2024, month: 5, day: 31, hour: 9, minute: 2, second: 3).date
        #expect(PhotoOrganizer.relativePath(for: URL(fileURLWithPath: "/r/f0001.JPG"), date: date, calendar: calendar)
                == "2024/05-31/2024-05-31_090203.jpg")
        #expect(PhotoOrganizer.relativePath(for: URL(fileURLWithPath: "/r/f0002.cr3"), date: nil) == "sin_fecha/f0002.cr3")
    }

    @Test("Copia por fecha, resuelve nombres repetidos, separa lo que no tiene fecha y no toca los originales")
    func organize() async throws {
        let source = try TestImages.makeTempFolder()
        let a = try TestImages.makePhoto(in: source, name: "f1.jpg", date: "2024:05:31 14:22:10")
        let b = try TestImages.makePhoto(in: source, name: "f2.jpg", date: "2024:05:31 14:22:10")
        let c = try TestImages.makePhoto(in: source, name: "f3.jpg", date: "2023:12:24 20:00:00")
        let d = try TestImages.makePhoto(in: source, name: "f4.jpg")
        let destination = try TestImages.makeTempFolder()

        let summary = try await PhotoOrganizer.organize([a, b, c, d], into: destination)
        #expect(summary == PhotoOrganizer.Summary(dated: 3, undated: 1))
        let fm = FileManager.default
        for path in ["2024/05-31/2024-05-31_142210.jpg", "2024/05-31/2024-05-31_142210_2.jpg",
                     "2023/12-24/2023-12-24_200000.jpg", "sin_fecha/f4.jpg"] {
            #expect(fm.fileExists(atPath: destination.appendingPathComponent(path).path), "falta \(path)")
        }
        #expect([a, b, c, d].allSatisfy { fm.fileExists(atPath: $0.path) })

        // Otra vez a la misma carpeta: no pisa nada, sigue numerando.
        _ = try await PhotoOrganizer.organize([a], into: destination)
        #expect(fm.fileExists(atPath: destination.appendingPathComponent("2024/05-31/2024-05-31_142210_3.jpg").path))
    }

    // MARK: Marca de la cámara

    @Test("Marca de la cámara por las carpetas de DCIM")
    func cameraBrand() {
        // Tarjeta real de una Canon EOS R6.
        #expect(CameraBrand.detect(dcimFolders: ["100EOSR6", "CANONMSC"]) == "Canon")
        #expect(CameraBrand.detect(dcimFolders: ["100CANON", "101CANON"]) == "Canon")
        #expect(CameraBrand.detect(dcimFolders: ["100MSDCF"]) == "Sony")
        #expect(CameraBrand.detect(dcimFolders: ["100ND850"]) == "Nikon")
        #expect(CameraBrand.detect(dcimFolders: ["100_FUJI", "101_FUJI"]) == "Fujifilm")
        #expect(CameraBrand.detect(dcimFolders: ["100gopro"]) == "GoPro")
        // Gana la que más carpetas tiene.
        #expect(CameraBrand.detect(dcimFolders: ["100MSDCF", "100CANON", "101CANON"]) == "Canon")
        // Lo que no se reconoce no da marca.
        #expect(CameraBrand.detect(dcimFolders: ["100APPLE", "Fotos"]) == nil)
        #expect(CameraBrand.detect(dcimFolders: []) == nil)
    }
}
