import Foundation
import Security
import CaobaCore

/// Cómo acabó una ejecución de PhotoRec.
enum PhotoRecOutcome: Equatable {
    /// Terminó; el informe dice si fue bien o con qué problemas. `exitCode` es el código con el
    /// que salió (PhotoRec da 0 aunque falle), para explicar los fallos que no dejan mensaje.
    case finished(PhotoRecReport, exitCode: Int?)
    /// El usuario la paró con «Cancelar» mientras buscaba.
    case cancelled
    /// Se cerró el diálogo de la contraseña: PhotoRec no llegó a arrancar.
    case notAuthorized
}

enum PhotoRecRunnerError: Error, Equatable {
    /// La app no lleva PhotoRec (compilada sin `Tools/build-photorec.sh`).
    case photoRecMissing
    /// macOS no dio la autorización o no dejó abrir la tarjeta. Lleva el motivo.
    case couldNotLaunch(String)
}

/// Lanza PhotoRec con permiso para leer la tarjeta. Va detrás de este protocolo para poder
/// cambiar el método (hoy, `authopen`; mañana, un helper con SMAppService cuando haya
/// Developer ID) sin tocar el resto del módulo.
@MainActor
protocol PhotoRecRunning: AnyObject {
    /// Lanza PhotoRec y espera a que acabe. `device` es lo único que necesita permiso de
    /// administrador; `outputFolder` tiene que existir.
    func run(arguments: [String], device: String, outputFolder: URL) async throws -> PhotoRecOutcome
    /// Pide que pare. `run` acaba poco después devolviendo `.cancelled`.
    func cancel()
}

/// Lanzador con `authopen`: la app pide autorización para **leer** esa tarjeta (el diálogo
/// sale con el nombre de CAOBA y pide la contraseña en cada recuperación), `authopen` la abre
/// y le pasa el descriptor a la app, y PhotoRec corre como proceso normal de la app leyendo
/// por ese descriptor. Nada de la app corre como root, y PhotoRec tiene los mismos permisos
/// de carpetas que CAOBA (puede guardar en el Escritorio, Documentos…).
@MainActor
final class AuthOpenPhotoRecRunner: PhotoRecRunning {
    private var launcher: PhotoRecLauncher?
    private var cancelRequested = false

    /// PhotoRec dentro de la app (`Resources/photorec/photorec`).
    static var bundledPhotoRec: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("photorec/photorec"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    func run(arguments: [String], device: String, outputFolder: URL) async throws -> PhotoRecOutcome {
        guard let photoRec = Self.bundledPhotoRec else { throw PhotoRecRunnerError.photoRecMissing }
        cancelRequested = false
        let prompt = L("CAOBA necesita permiso de administrador para leer la tarjeta. No se escribirá nada en ella.")

        // 1. Autorización y apertura, fuera del hilo principal (el diálogo espera al usuario).
        let opened = await Task.detached { Self.openReadOnly(device, prompt: prompt) }.value
        let handle: FileHandle
        switch opened {
        case .success(let h): handle = h
        case .failure(.cancelledByUser): return .notAuthorized
        case .failure(.failed(let message)): throw PhotoRecRunnerError.couldNotLaunch(message)
        }
        defer { try? handle.close() }
        if cancelRequested { return .cancelled }

        // 2. PhotoRec como proceso de la app, leyendo la tarjeta por el descriptor.
        let launcher = PhotoRecLauncher()
        self.launcher = launcher
        defer { self.launcher = nil }
        let exit = try await launcher.run(photoRec: photoRec, arguments: arguments, devicePath: device,
                                          device: handle, outputFolder: outputFolder)
        if cancelRequested || exit.wasTerminated { return .cancelled }
        return .finished(Self.report(in: outputFolder), exitCode: Int(exit.status))
    }

    func cancel() {
        cancelRequested = true
        launcher?.terminate()
    }

    /// Lee el log y la salida que dejó PhotoRec.
    private static func report(in folder: URL) -> PhotoRecReport {
        func read(_ name: String) -> String {
            (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
        }
        return PhotoRecReport.parse(log: read(PhotoRecCommand.logFileName), output: read(PhotoRecLauncher.outputFileName))
    }

    // MARK: Autorización

    enum OpenFailure: Error {
        case cancelledByUser
        case failed(String)
    }

    /// Pide el derecho `sys.openfile.readonly.<dispositivo>` (con el diálogo de macOS, con el
    /// nombre de CAOBA y nuestro texto), se lo pasa a `authopen` y devuelve el descriptor.
    /// Solo lectura: con ese derecho `authopen` no puede abrirla para escribir.
    nonisolated private static func openReadOnly(_ device: String, prompt: String) -> Result<FileHandle, OpenFailure> {
        var authorization: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess, let authorization else {
            return .failure(.failed("AuthorizationCreate"))
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        let rightName = "sys.openfile.readonly." + device
        let status: OSStatus = rightName.withCString { name in
            prompt.withCString { promptText in
                var right = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                var promptItem = AuthorizationItem(name: kAuthorizationEnvironmentPrompt, valueLength: strlen(promptText),
                                                   value: UnsafeMutableRawPointer(mutating: promptText), flags: 0)
                return withUnsafeMutablePointer(to: &right) { rightPointer in
                    withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                        var rights = AuthorizationRights(count: 1, items: rightPointer)
                        var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                        return AuthorizationCopyRights(authorization, &rights, &environment,
                                                       [.interactionAllowed, .extendRights, .preAuthorize], nil)
                    }
                }
            }
        }
        if status == errAuthorizationCanceled { return .failure(.cancelledByUser) }
        guard status == errAuthorizationSuccess else {
            return .failure(.failed((SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"))
        }

        var external = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(authorization, &external) == errAuthorizationSuccess else {
            return .failure(.failed("AuthorizationMakeExternalForm"))
        }
        let externalData = withUnsafeBytes(of: &external) { Data($0) }
        do {
            return .success(try AuthOpen.openReadOnly(device, externalAuthorization: externalData))
        } catch AuthOpen.Failure.notOpened(let message), AuthOpen.Failure.couldNotLaunch(let message) {
            return .failure(.failed(message))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }
}
