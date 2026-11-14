import Foundation
import CryptoKit

/// Copia un fichero de forma segura: nunca deja con su nombre bueno una copia a medias o mal.
///
/// 1. Lee el original por trozos, calcula su suma (SHA-256) y escribe en `<nombre>.caoba-part`.
/// 2. Fuerza la escritura al disco físico (`F_FULLFSYNC`, no basta con que esté en caché).
/// 3. Relee la copia y compara sumas. Si no coinciden, la borra y lo dice.
/// 4. Le pone la fecha del original y solo entonces le da el nombre definitivo.
public enum VerifiedCopier {
    public enum Failure: Error, Equatable {
        /// La copia no es igual que el original (fallo del lector, del cable o del disco).
        case verificationFailed
        /// Se canceló a mitad; no queda nada en el destino.
        case cancelled
    }

    /// Extensión de las copias a medias. Si se corta (cancelar, sacar la tarjeta, apagón),
    /// se quedan así y la siguiente descarga las borra y las rehace.
    public static let partialExtension = "caoba-part"

    static let chunkSize = 4 << 20

    /// Copia `source` a `destination` (que no debe existir). `progress` recibe los bytes
    /// copiados de cada trozo; `isCancelled` se consulta entre trozos.
    public static func copy(_ source: CardFile, to destination: URL,
                            progress: (Int64) -> Void = { _ in }, isCancelled: () -> Bool = { false }) throws {
        let fm = FileManager.default
        let partial = destination.appendingPathExtension(partialExtension)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: partial)
        fm.createFile(atPath: partial.path, contents: nil)
        var done = false
        defer { if !done { try? fm.removeItem(at: partial) } }

        // 1 y 2: copiar calculando la suma y forzar a disco.
        let input = try FileHandle(forReadingFrom: source.url)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: partial)
        var sourceHash = SHA256()
        do {
            defer { try? output.close() }
            while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                if isCancelled() { throw Failure.cancelled }
                sourceHash.update(data: chunk)
                try output.write(contentsOf: chunk)
                progress(Int64(chunk.count))
            }
            if fcntl(output.fileDescriptor, F_FULLFSYNC) != 0 { try output.synchronize() }
        }

        // 3: releer lo escrito y comparar.
        guard try hash(of: partial, isCancelled: isCancelled) == sourceHash.finalize() else {
            throw Failure.verificationFailed
        }

        // 4: fecha del original y nombre definitivo.
        try fm.setAttributes([.modificationDate: source.date], ofItemAtPath: partial.path)
        try fm.moveItem(at: partial, to: destination)
        done = true
    }

    /// Suma SHA-256 de un fichero, leyendo por trozos.
    static func hash(of url: URL, isCancelled: () -> Bool = { false }) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            if isCancelled() { throw Failure.cancelled }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    /// Borra las copias a medias que haya dejado una descarga cortada en esas carpetas.
    public static func removePartials(in folders: Set<URL>) {
        let fm = FileManager.default
        for folder in folders {
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for item in items where item.pathExtension == partialExtension { try? fm.removeItem(at: item) }
        }
    }
}
