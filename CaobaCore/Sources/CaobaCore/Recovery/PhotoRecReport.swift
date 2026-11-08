import Foundation

/// Problemas que puede contar PhotoRec, ya agrupados para explicarlos a quien no
/// es técnico (la app pone el texto). PhotoRec sale con código 0 aunque falle, así
/// que esto es lo único fiable para saber si ha ido bien.
public enum PhotoRecProblem: Sendable, Equatable {
    /// No pudo abrir la tarjeta (sin permisos, desconectada…).
    case cannotOpenDevice
    /// La carpeta de destino no existe (o ha desaparecido a mitad).
    case destinationMissing
    /// No tiene permiso para escribir en la carpeta de destino.
    case destinationNotWritable
    /// El disco de destino se ha llenado.
    case destinationFull
    /// Se eligió ext2/3/4 pero la tarjeta no lo es.
    case notExtFileSystem
    /// Lo han parado desde fuera (al cancelar, o el sistema).
    case stopped
    /// Cualquier otro error, con la línea tal cual para el log de la app.
    case other(String)
}

/// Lo que se saca del log (y de la salida) de PhotoRec al terminar.
public struct PhotoRecReport: Sendable, Equatable {
    /// Llegó al final («PhotoRec exited normally.») sin ningún problema.
    public var finishedNormally: Bool
    public var problems: [PhotoRecProblem]
    /// Recuperados por familia de PhotoRec («jpg: 1/1 recovered» → `["jpg": 1]`).
    public var recoveredByFamily: [String: Int]
    /// «Total: N files found».
    public var total: Int?

    public var succeeded: Bool { finishedNormally && problems.isEmpty }

    /// Lee el log de PhotoRec y lo que escribió por la salida estándar (el fallo al
    /// abrir el dispositivo solo sale por ahí, antes de que exista el log).
    public static func parse(log: String, output: String = "") -> PhotoRecReport {
        var report = PhotoRecReport(finishedNormally: false, problems: [], recoveredByFamily: [:], total: nil)
        for line in (log + "\n" + output).split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("PhotoRec exited normally") {
                report.finishedNormally = true
            } else if let (family, count) = recoveredCount(in: line) {
                report.recoveredByFamily[family] = count
            } else if line.hasPrefix("Total: "), let n = Int(line.dropFirst(7).prefix { $0.isNumber }) {
                report.total = n
            } else if let problem = problem(in: line), !report.problems.contains(problem) {
                report.problems.append(problem)
            }
        }
        return report
    }

    /// «jpg: 2/3 recovered» → ("jpg", 2).
    private static func recoveredCount(in line: String) -> (String, Int)? {
        guard line.hasSuffix(" recovered"), let colon = line.firstIndex(of: ":") else { return nil }
        let family = String(line[..<colon])
        let numbers = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let count = Int(numbers.prefix { $0.isNumber }), !family.contains(" ") else { return nil }
        return (family, count)
    }

    /// Traduce las líneas de error conocidas (textos de `phmain.c`, `phbf.c`, `psearchn.c`).
    private static func problem(in line: String) -> PhotoRecProblem? {
        if line.hasPrefix("Unable to open file or device") || line.hasPrefix("No disk found") {
            return .cannotOpenDevice
        }
        if line.hasPrefix("Cannot create file") || line.hasPrefix("Cannot write to file") {
            // El final de la línea es el `strerror` del sistema.
            if line.hasSuffix("No space left on device") { return .destinationFull }
            if line.hasSuffix("Permission denied") || line.hasSuffix("Read-only file system") { return .destinationNotWritable }
            if line.hasSuffix("No such file or directory") { return .destinationMissing }
            return .other(line)
        }
        if line.hasPrefix("Not a valid ext2/ext3/ext4 filesystem") { return .notExtFileSystem }
        if line.contains("detected! PhotoRec has been killed") { return .stopped }
        if line.hasPrefix("Syntax error") { return .other(line) }
        return nil
    }
}
