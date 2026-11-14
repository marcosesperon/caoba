import SwiftUI
import CaobaCore

/// Recuperar fotos: elegir tarjeta y opciones, ver cómo avanza y el resultado.
/// El estado vive en `AppState.recovery` para que la búsqueda siga al cambiar de módulo.
struct RecoveryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let session = appState.recovery
        VStack(alignment: .leading, spacing: 12) {
            ModuleTitle(title: "Recuperar fotos")
            switch session.phase {
            case .setup:
                ScrollView { RecoverySetupView(session: session) }
                RecoveryActionBar(session: session)
            case .starting, .running, .paused, .cancelling:
                RecoveryProgressView(session: session)
                // Lo encontrado va saliendo debajo, para ir eliminando lo que no interesa.
                if let results = session.results {
                    RecoveryResultsView(results: results)
                } else {
                    Spacer()
                }
            case .finished(let result):
                RecoveryFinishedView(session: session, result: result)
                if let results = session.results {
                    RecoveryResultsView(results: results)
                } else {
                    Spacer()
                }
            }
        }
        .onAppear {
            session.diskMonitor.start()
            // Para capturas desde línea de comandos: `--state recovery.results=<carpeta recuperada>`.
            if let path = appState.launchState["recovery.results"] {
                appState.launchState["recovery.results"] = nil
                session.showResults(of: URL(fileURLWithPath: path))
            }
            #if DEBUG
            // Búsqueda de mentira (solo desarrollo): `--state recovery.demo=<fotos>` y `recovery.demoOut=<destino>`.
            if let source = appState.launchState["recovery.demo"], let out = appState.launchState["recovery.demoOut"] {
                appState.launchState["recovery.demo"] = nil
                session.startDemo(source: URL(fileURLWithPath: source), destination: URL(fileURLWithPath: out))
            }
            #endif
        }
    }
}

// MARK: - Opciones

/// Tarjeta, qué buscar y dónde buscar.
struct RecoverySetupView: View {
    @Bindable var session: RecoverySession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Deja de usar la tarjeta hasta terminar: no hagas fotos ni copies nada en ella. Cualquier cosa nueva puede escribirse encima de lo borrado.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .caobaPanel()
            diskSection
            typesSection
            whereSection
        }
    }

    private var diskSection: some View {
        OptionGroup(title: "Tarjeta") {
            if session.diskMonitor.disks.isEmpty {
                Label("Conecta la tarjeta o el lector. Aparecerá aquí sola.", systemImage: "sdcard")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.diskMonitor.disks) { disk in
                    DiskRow(disk: disk, isSelected: disk.id == session.selectedDiskID)
                        .contentShape(Rectangle())
                        .onTapGesture { session.selectedDiskID = disk.id }
                }
            }
        } accessory: {
            // Vuelve a preguntar a macOS por los discos (por si algo no sale o se ha quedado viejo). No monta nada.
            Button("Recargar") { session.diskMonitor.reload() }
                .controlSize(.small)
        }
    }

    private var typesSection: some View {
        OptionGroup(title: "Qué buscar") {
            ForEach(RecoveryFileGroup.allCases, id: \.self) { group in
                Toggle(isOn: Binding(get: { session.groups.contains(group) },
                                     set: { if $0 { session.groups.insert(group) } else { session.groups.remove(group) } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.title)
                        Text(group.examples).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Toggle(isOn: $session.includeOtherFiles) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Otros archivos")
                    Text("Documentos, audio, comprimidos… todo lo que reconoce PhotoRec. La búsqueda tarda más y salen muchos ficheros.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var whereSection: some View {
        OptionGroup(title: "Dónde buscar") {
            let freeSpaceAvailable = session.selectedDisk?.supportsFreeSpace ?? true
            Picker("", selection: $session.scope) {
                Text("Solo espacio libre").tag(RecoveryScope.freeSpace)
                Text("Toda la tarjeta").tag(RecoveryScope.wholeDisk)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .disabled(!freeSpaceAvailable)
            if freeSpaceAvailable {
                Text(session.scope == .freeSpace
                     ? "Lo normal tras borrar fotos: busca solo donde estaba lo borrado. Es más rápido y no repite lo que sigue en la tarjeta."
                     : "Para tarjetas formateadas, dañadas o que el Mac no reconoce: busca en todo. Tarda más y también recupera lo que no se ha borrado.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Esta tarjeta no es FAT ni exFAT (o el Mac no la reconoce), así que se buscará en toda la tarjeta.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledRow("Sistema de archivos") {
                Picker("", selection: $session.fileSystem) {
                    Text("FAT, exFAT, NTFS, HFS+ (lo normal)").tag(RecoveryFileSystem.other)
                    Text("ext2/3/4 (Linux)").tag(RecoveryFileSystem.ext)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

/// Fila de una tarjeta, con todas las pistas para reconocerla: arriba el nombre del volumen
/// y la cámara; debajo, en gris, conexión, tamaño, sistema de archivos y espacio usado.
private struct DiskRow: View {
    let disk: ExternalDisk
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            Image(systemName: disk.isDiskImage ? "opticaldiscdrive" : "sdcard").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(disk.name).fontWeight(isSelected ? .semibold : .regular)
                    if let brand = disk.cameraBrand { Text(verbatim: "· \(brand)") }
                }
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    /// «Lector SD del Mac · 124,7 GB · ExFAT · 70 GB usados de 124,6 GB»; lo que no se sabe no sale.
    private var details: String {
        var parts = [disk.connection, Self.bytes(disk.size),
                     disk.volumeType ?? L("Sistema de archivos desconocido")]
        if let used = disk.usedBytes, let capacity = disk.volumeCapacity {
            parts.append(L("\(Self.bytes(used)) usados de \(Self.bytes(capacity))"))
        }
        return parts.joined(separator: " · ")
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

// MARK: - Barra de acción

/// Destino, avisos y el botón «Recuperar».
struct RecoveryActionBar: View {
    @Bindable var session: RecoverySession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem = session.blockingProblem {
                Label(problem, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            } else if let warning = session.spaceWarning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(session.destinationFolder?.path ?? String(localized: "Elige dónde guardar lo recuperado (en otro disco, no en la tarjeta)"))
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(session.destinationFolder == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Elegir…") { chooseDestination() }.fixedSize()
                Divider().frame(height: 18)
                Button("Recuperar") { session.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.blockingProblem != nil)
                    .fixedSize()
            }
            Text("Te pedirá la contraseña de administrador: leer la tarjeta en bruto lo exige. La tarjeta se usa solo para leer.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .caobaPanel()
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Elegir destino")
        if panel.runModal() == .OK, let url = panel.url { session.destinationFolder = url }
    }
}

// MARK: - En marcha

/// Estado, tiempo, recuento, espacio en el destino, «Pausar» / «Continuar» y «Cancelar».
/// Compacto, porque debajo va la cuadrícula de lo que se va encontrando.
struct RecoveryProgressView: View {
    let session: RecoverySession

    var body: some View {
        OptionGroup(title: title) {
            HStack(spacing: 10) {
                if session.isPaused {
                    Image(systemName: "pause.circle").foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(statusText)
                Spacer()
                if let start = session.startDate {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(start)).formatted(.time(pattern: .hourMinuteSecond)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                buttons
            }
            if case .paused(automatic: true) = session.phase {
                Label(lowSpaceText, systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(alignment: .bottom) {
                RecoveryCountsView(counts: session.counts)
                Spacer()
                spaceText.font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            if let disk = session.selectedDisk {
                Text("«\(disk.name)» está desmontada mientras tanto. No la saques hasta que termine.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch session.phase {
        case .running:
            Button("Pausar") { session.pause() }
        case .paused:
            Button("Continuar") { session.resume() }
                .buttonStyle(.borderedProminent)
                .disabled(!session.hasEnoughFreeSpace)
                .help("Sigue donde se quedó. Hace falta sitio libre en el destino.")
        default:
            EmptyView()
        }
        Button("Cancelar") { session.cancel() }
            .disabled(!(session.phase == .running || session.isPaused))
    }

    /// «Ocupa 12,4 GB · Quedan 38 GB libres».
    private var spaceText: Text {
        let used = ByteCountFormatter.string(fromByteCount: session.usedSpace, countStyle: .file)
        guard let free = session.freeSpace else { return Text("Ocupa \(used)") }
        return Text("Ocupa \(used) · Quedan \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) libres")
    }

    private var lowSpaceText: String {
        let minimum = ByteCountFormatter.string(fromByteCount: RecoverySession.minimumFreeSpace, countStyle: .file)
        return session.hasEnoughFreeSpace
            ? L("Ya hay sitio. Pulsa «Continuar» para seguir donde se quedó.")
            : L("En pausa: el disco de destino se está llenando. Elimina lo que no quieras (o libera espacio en ese disco) hasta tener al menos \(minimum) libres y pulsa «Continuar».")
    }

    private var title: LocalizedStringKey {
        session.isPaused ? "En pausa" : "Buscando"
    }

    private var statusText: LocalizedStringKey {
        switch session.phase {
        case .starting: return "Esperando la contraseña de administrador…"
        case .cancelling: return "Parando…"
        case .paused: return "PhotoRec está detenido donde se quedó; no se pierde nada."
        default: return "Buscando fotos y vídeos borrados. Puede tardar bastante con tarjetas grandes."
        }
    }
}

/// Total grande y recuento por tipo.
struct RecoveryCountsView: View {
    let counts: RecoveredFiles.Counts

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading) {
                Text(counts.total.formatted()).font(.caobaTitle(40)).monospacedDigit()
                Text("ficheros recuperados").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(RecoveryFileGroup.allCases, id: \.self) { group in
                countBadge(group.title, counts.byGroup[group] ?? 0)
            }
            countBadge("Otros", counts.other)
        }
    }

    private func countBadge(_ title: LocalizedStringKey, _ value: Int) -> some View {
        VStack(alignment: .leading) {
            Text(value.formatted()).font(.title2).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Resultado

/// Cómo terminó y qué hacer ahora. La cuadrícula va debajo (`RecoveryResultsView`).
struct RecoveryFinishedView: View {
    let session: RecoverySession
    let result: RecoveryResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionGroup(title: title) {
                Label(message, systemImage: icon).foregroundStyle(color)
                if let counts = result.counts { RecoveryCountsView(counts: counts) }
            }
            HStack {
                if let folder = session.outputFolder, result.counts != nil {
                    Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
                Spacer()
                Button("Nueva recuperación") { session.reset() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch result {
        case .completed: return "Terminado"
        case .completedWithProblem: return "Terminado con problemas"
        case .cancelled: return "Cancelado"
        case .failed: return "No se ha podido recuperar"
        }
    }

    private var message: String {
        switch result {
        case .completed(let counts):
            return counts.total == 0
                ? L("No se ha encontrado nada. Prueba con «Toda la tarjeta» o con «Otros archivos».")
                : L("Búsqueda completa. Lo recuperado está en su carpeta; las fotos pueden tener nombres como f0002051.jpg.")
        case .completedWithProblem(_, let message), .failed(let message):
            return message
        case .cancelled:
            return L("Has parado la búsqueda. Lo recuperado hasta ese momento se conserva.")
        }
    }

    private var icon: String {
        switch result {
        case .completed: return "checkmark.circle"
        case .cancelled: return "stop.circle"
        default: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch result {
        case .completed: return .green
        case .cancelled: return .secondary
        default: return .orange
        }
    }
}

extension RecoveryFileGroup {
    /// Nombre del grupo en la interfaz.
    var title: LocalizedStringKey {
        switch self {
        case .jpeg: return "JPG"
        case .raw: return "RAW"
        case .heic: return "HEIC"
        case .video: return "Vídeo"
        }
    }

    /// Ejemplos de formatos, para que se entienda qué entra en cada grupo.
    var examples: LocalizedStringKey {
        switch self {
        case .jpeg: return "Las fotos normales de casi todas las cámaras."
        case .raw: return "CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2, PEF… (y TIFF)"
        case .heic: return "Fotos de iPhone y de algunas cámaras."
        case .video: return "MOV, MP4, MTS, AVI…"
        }
    }
}
