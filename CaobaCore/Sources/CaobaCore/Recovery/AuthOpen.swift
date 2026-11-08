import Foundation
import Darwin

/// Abre un fichero o dispositivo en **solo lectura** con `/usr/libexec/authopen`, la herramienta
/// de macOS hecha para esto: comprueba la autorización (`sys.openfile.readonly.<ruta>`), abre
/// la ruta y le devuelve a quien la llama el descriptor ya abierto por un socket (`SCM_RIGHTS`).
///
/// Así la app puede leer la tarjeta en bruto (`/dev/rdiskN`, que es de root) sin ejecutar
/// nada suyo como root, y PhotoRec corre como un proceso normal de la app, con sus permisos
/// de carpetas. La autorización la pide la app (con su nombre en el diálogo) y se la pasa
/// a `authopen` en forma externa (`-extauth`). Si el usuario ya puede abrir la ruta,
/// `authopen` no pide nada (así se prueba sin contraseña).
public enum AuthOpen {
    public enum Failure: Error, Equatable {
        /// No se pudo lanzar `authopen` o crear el socket.
        case couldNotLaunch(String)
        /// `authopen` no la abrió (sin autorización, no existe…). Lleva lo que dijo.
        case notOpened(String)
    }

    static let tool = URL(fileURLWithPath: "/usr/libexec/authopen")

    /// Abre `path` en solo lectura. `externalAuthorization` es la `AuthorizationExternalForm`
    /// (32 bytes) de una autorización ya concedida; sin ella, `authopen` la pediría por su
    /// cuenta. Bloquea hasta que `authopen` acaba: llamarla fuera del hilo principal.
    public static func openReadOnly(_ path: String, externalAuthorization: Data? = nil) throws -> FileHandle {
        var sockets: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw Failure.couldNotLaunch(String(cString: strerror(errno)))
        }
        let ownEnd = sockets[0]
        defer { close(ownEnd) }

        let process = Process()
        process.executableURL = tool
        process.arguments = ["-stdoutpipe"] + (externalAuthorization == nil ? [] : ["-extauth"]) + [path]
        // La salida de authopen es su extremo del socket: por ahí manda el descriptor.
        let childEnd = FileHandle(fileDescriptor: sockets[1], closeOnDealloc: true)
        process.standardOutput = childEnd
        let input = Pipe()
        process.standardInput = input
        let errors = Pipe()
        process.standardError = errors
        do {
            try process.run()
        } catch {
            try? childEnd.close()
            throw Failure.couldNotLaunch(error.localizedDescription)
        }
        // Nuestra copia del extremo de authopen sobra: así, si sale sin mandar nada, llega el fin.
        try? childEnd.close()
        if let externalAuthorization { input.fileHandleForWriting.write(externalAuthorization) }
        try? input.fileHandleForWriting.close()

        let descriptor = receiveDescriptor(on: ownEnd)
        process.waitUntilExit()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, let descriptor else {
            if let descriptor { close(descriptor) }
            throw Failure.notOpened(message.isEmpty ? "authopen: \(process.terminationStatus)" : message)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Recibe un descriptor mandado con `SCM_RIGHTS`; `nil` si llega el fin sin ninguno.
    /// Las macros `CMSG_*` de C no existen en Swift: el tamaño y la alineación (a 4 bytes en
    /// Darwin, `__DARWIN_ALIGN32`) se calculan a mano.
    static func receiveDescriptor(on socket: Int32) -> Int32? {
        func align(_ n: Int) -> Int { (n + 3) & ~3 }
        let headerSize = align(MemoryLayout<cmsghdr>.size)
        let controlSize = headerSize + align(MemoryLayout<Int32>.size)
        let control = UnsafeMutableRawPointer.allocate(byteCount: controlSize, alignment: MemoryLayout<cmsghdr>.alignment)
        defer { control.deallocate() }
        let data = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 1)
        defer { data.deallocate() }

        var iov = iovec(iov_base: data, iov_len: 64)
        return withUnsafeMutablePointer(to: &iov) { iovPointer -> Int32? in
            var message = msghdr(msg_name: nil, msg_namelen: 0, msg_iov: iovPointer, msg_iovlen: 1,
                                 msg_control: control, msg_controllen: socklen_t(controlSize), msg_flags: 0)
            var received: Int
            repeat { received = recvmsg(socket, &message, 0) } while received < 0 && errno == EINTR
            guard received > 0, Int(message.msg_controllen) >= headerSize + MemoryLayout<Int32>.size else { return nil }
            let header = control.load(as: cmsghdr.self)
            guard header.cmsg_level == SOL_SOCKET, header.cmsg_type == SCM_RIGHTS else { return nil }
            return control.load(fromByteOffset: headerSize, as: Int32.self)
        }
    }
}
