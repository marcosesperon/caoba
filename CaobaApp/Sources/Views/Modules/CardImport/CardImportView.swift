import SwiftUI
import QuickLook
import CaobaCore

/// Descargar tarjeta: copia las fotos y vídeos de una tarjeta a una carpeta del disco, de forma
/// comprobada y sin repetir lo que ya está. El estado vive en `AppState.cardImport`.
struct CardImportView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let session = appState.cardImport
        VStack(alignment: .leading, spacing: 12) {
            ModuleTitle(title: "Descargar tarjeta")
            switch session.phase {
            case .setup:
                ScrollView { CardImportSetupView(session: session) }
                CardImportActionBar(session: session)
            case .copying, .paused, .cancelling:
                CardImportProgressView(session: session)
                Spacer()
            case .finished(let summary):
                CardImportFinishedView(session: session, summary: summary)
                Spacer()
            }
        }
        .onAppear {
            session.diskMonitor.start()
            session.disksChanged()
            session.scheduleScan()
            // Para pruebas y capturas: `--state cardImport.card=disk7` elige esa tarjeta y,
            // con `cardImport.start=1`, empieza a descargar en cuanto ha leído la tarjeta.
            if let card = appState.launchState["cardImport.card"] {
                appState.launchState["cardImport.card"] = nil
                Task {
                    // La lista de discos tarda un momento en llenarse.
                    try? await Task.sleep(for: .seconds(1))
                    session.selectedDiskID = card
                    if appState.launchState["cardImport.start"] != nil {
                        while session.isScanning || session.plan == nil { try? await Task.sleep(for: .milliseconds(100)) }
                        session.start()
                    }
                }
            }
        }
    }
}

// MARK: - Opciones

/// Tarjeta, qué descargar y cómo organizarlo.
struct CardImportSetupView: View {
    @Bindable var session: CardImportSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionGroup(title: "Tarjeta") {
                if session.mountedDisks.isEmpty {
                    Label("Mete la tarjeta en el lector. Aparecerá aquí sola.", systemImage: "sdcard")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.mountedDisks) { disk in
                        ExternalDiskRow(disk: disk, isSelected: disk.id == session.selectedDiskID)
                            .contentShape(Rectangle())
                            .onTapGesture { session.selectedDiskID = disk.id }
                    }
                }
            } accessory: {
                Button("Recargar") { session.diskMonitor.reload() }
                    .controlSize(.small)
            }
            if !session.sessions.isEmpty {
                CardSessionsView(session: session)
            }
            OptionGroup(title: "Qué descargar") {
                ForEach(RecoveryFileGroup.allCases, id: \.self) { group in
                    Toggle(isOn: Binding(get: { session.groups.contains(group) },
                                         set: { if $0 { session.groups.insert(group) } else { session.groups.remove(group) } })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(group.title)
                            Text(group.examples).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Cada foto o vídeo se lleva sus ficheros acompañantes con el mismo nombre (.XMP, .WAV, .THM, .LRF).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            OptionGroup(title: "Cómo organizarlas") {
                Picker("", selection: $session.layout) {
                    Text("Todo junto en la carpeta").tag(CardImportLayout.flat)
                    Text("Por fecha (AAAA/MM-DD)").tag(CardImportLayout.byDate)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("Siempre con el nombre original. Lo que ya esté descargado se salta, y una foto distinta con el mismo nombre (de otra cámara) se guarda con sufijo _2. Nunca se sobrescribe nada.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Sesiones de la tarjeta para elegir qué descargar: casilla, fecha y horas, fotos, lo que falta,
/// una tira de miniaturas y «Ver todas». Arriba, cuánto hueco separa una sesión de otra.
struct CardSessionsView: View {
    @Bindable var session: CardImportSession
    /// Foto abierta en QuickLook y la lista que se recorre con las flechas (la sesión entera).
    @State private var previewURL: URL?
    @State private var previewList: [URL] = []
    // En @State para que la caché de miniaturas no se pierda cada vez que se redibuja la vista.
    @State private var thumbnails = QuickLookThumbnails()

    var body: some View {
        OptionGroup(title: "Sesiones en la tarjeta") {
            ForEach(session.sessions) { item in
                sessionRow(item)
                if item.id != session.sessions.last?.id { Divider() }
            }
            HStack {
                Button("Marcar todas") { session.selectAllSessions() }
                Button("Desmarcar todas") { session.deselectAllSessions() }
            }
            .controlSize(.small)
        } accessory: {
            HStack(spacing: 6) {
                Text("Separar sesiones con más de").font(.callout).foregroundStyle(.secondary)
                Picker("", selection: $session.sessionGap) {
                    Text("1 h").tag(CardSessionGap.oneHour)
                    Text("2 h").tag(CardSessionGap.twoHours)
                    Text("4 h").tag(CardSessionGap.fourHours)
                    Text("8 h").tag(CardSessionGap.eightHours)
                    Text("Por días").tag(CardSessionGap.byDay)
                }
                .labelsHidden()
                .fixedSize()
            }
            .controlSize(.small)
        }
        .quickLookPreview($previewURL, in: previewList)
    }

    private func sessionRow(_ item: CardSession) -> some View {
        let pending = session.pending(in: item)
        return HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(get: { session.isSelected(item) }, set: { _ in session.toggle(item) }))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.dateRange(item)).fontWeight(.medium)
                Text(statusText(item, pending: pending))
                    .font(.callout)
                    .foregroundStyle(pending == 0 ? .secondary : .primary)
                Button("Ver todas") {
                    previewList = item.items.map(\.file.url)
                    previewURL = previewList.first
                }
                .controlSize(.small)
            }
            .frame(minWidth: 260, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(item.sample(6), id: \.file.url) { photo in
                    CardThumbnail(url: photo.file.url, thumbnails: thumbnails)
                        .onTapGesture(count: 2) {
                            previewList = item.items.map(\.file.url)
                            previewURL = photo.file.url
                        }
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(pending == 0 && !session.isSelected(item) ? 0.6 : 1)
    }

    /// «412 fotos · 9,8 GB · faltan 412», «faltan 12 de 230» o «ya descargada».
    private func statusText(_ item: CardSession, pending: Int) -> String {
        let base = L("\(item.items.count) fotos · \(CardImportSession.bytes(item.totalSize))")
        if pending == 0 { return base + " · " + L("ya descargada") }
        if pending == item.items.count { return base + " · " + L("faltan \(pending)") }
        return base + " · " + L("faltan \(pending) de \(item.items.count)")
    }

    /// «sáb, 14 nov 2026 · 10:02–13:47», o con las dos fechas si pasa de un día a otro.
    static func dateRange(_ item: CardSession) -> String {
        let day = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).year()
        let time = Date.FormatStyle().hour().minute()
        if Calendar.current.isDate(item.start, inSameDayAs: item.end) {
            return item.start.formatted(day) + " · " + item.start.formatted(time) + "–" + item.end.formatted(time)
        }
        return item.start.formatted(day) + " " + item.start.formatted(time) + " – " + item.end.formatted(day) + " " + item.end.formatted(time)
    }
}

/// Miniatura de una foto de la tarjeta (QuickLook usa la vista previa que lleva dentro el RAW).
/// Se carga al aparecer y se cancela si sale de la pantalla.
private struct CardThumbnail: View {
    let url: URL
    let thumbnails: QuickLookThumbnails
    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
            if let image {
                Image(decorative: image, scale: scale).resizable().scaledToFit()
            }
        }
        .frame(width: 72, height: 54)
        .help(url.lastPathComponent)
        .task(id: url) { image = await thumbnails.thumbnail(for: url, size: 72, scale: scale) }
    }
}

/// Resumen, destino, avisos y el botón «Descargar».
struct CardImportActionBar: View {
    @Bindable var session: CardImportSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let plan = session.plan, session.selectedDisk != nil, !session.selectedSessionIDs.isEmpty {
                Text(summaryText(plan)).font(.callout)
            }
            if let problem = session.blockingProblem {
                Label(problem, systemImage: session.isScanning ? "hourglass" : "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let warning = session.spaceWarning {
                Label(warning, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(session.destinationFolder?.path ?? String(localized: "Elige dónde descargar las fotos"))
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(session.destinationFolder == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Elegir…") { chooseDestination() }.fixedSize()
                Divider().frame(height: 18)
                Button("Descargar") { session.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.blockingProblem != nil)
                    .fixedSize()
            }
            Text("Cada copia se comprueba con la de la tarjeta antes de darla por buena. La tarjeta solo se lee.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .caobaPanel()
    }

    /// «2 sesiones marcadas · faltan 424 (10,1 GB)».
    private func summaryText(_ plan: CardImportPlan) -> String {
        L("\(session.selectedSessionIDs.count) sesiones marcadas · faltan \(plan.tasks.count) (\(CardImportSession.bytes(plan.bytesToCopy)))")
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

/// Fichero actual, cuántas van, GB, velocidad, tiempo restante, «Pausar» / «Continuar» y «Cancelar».
struct CardImportProgressView: View {
    let session: CardImportSession

    var body: some View {
        let progress = session.progress
        OptionGroup(title: session.isPaused ? "En pausa" : "Descargando") {
            HStack(spacing: 10) {
                Text(statusText).lineLimit(1).truncationMode(.middle)
                Spacer()
                buttons
            }
            ProgressView(value: progress.bytesTotal > 0 ? Double(progress.bytesDone) / Double(progress.bytesTotal) : 0)
            HStack {
                Text("\(progress.filesDone) de \(progress.filesTotal) · \(CardImportSession.bytes(progress.bytesDone)) de \(CardImportSession.bytes(progress.bytesTotal))")
                    .monospacedDigit()
                Spacer()
                if let speed = session.speed {
                    Text(speedText(speed)).monospacedDigit()
                }
            }
            .font(.callout).foregroundStyle(.secondary)
            if case .paused(automatic: true) = session.phase {
                Label(lowSpaceText, systemImage: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            if let disk = session.selectedDisk {
                Text("No saques «\(disk.name)» hasta que termine. Si se corta, vuelve a descargar: lo ya copiado se salta.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch session.phase {
        case .copying:
            Button("Pausar") { session.pause() }
        case .paused:
            Button("Continuar") { session.resume() }
                .buttonStyle(.borderedProminent)
                .disabled(!session.hasEnoughSpaceToResume)
        default:
            EmptyView()
        }
        Button("Cancelar") { session.cancel() }
            .disabled(!(session.phase == .copying || session.isPaused))
    }

    private var statusText: String {
        switch session.phase {
        case .cancelling: return L("Parando…")
        case .paused(automatic: false): return L("En pausa. Lo copiado está a salvo.")
        default: return session.progress.currentName
        }
    }

    /// «85 MB/s · quedan 4 min».
    private func speedText(_ speed: Double) -> String {
        let perSecond = CardImportSession.bytes(Int64(speed)) + "/s"
        guard let remaining = session.remainingSeconds, session.phase == .copying else { return perSecond }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.maximumUnitCount = 2
        return L("\(perSecond) · quedan \(formatter.string(from: remaining) ?? "")")
    }

    private var lowSpaceText: String {
        let free = CardImportSession.bytes(session.freeSpace ?? 0)
        let needed = CardImportSession.bytes(session.neededSpace ?? 0)
        return session.hasEnoughSpaceToResume
            ? L("Ya hay sitio. Pulsa «Continuar» para seguir donde se quedó.")
            : L("En pausa: no cabe la siguiente foto. Quedan \(free) libres y hacen falta \(needed). Libera espacio en el disco de destino y pulsa «Continuar».")
    }
}

// MARK: - Resultado

/// Cómo acabó, qué falló y qué hacer ahora: Finder, expulsar, otra tarjeta.
struct CardImportFinishedView: View {
    @Bindable var session: CardImportSession
    let summary: CardImportSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OptionGroup(title: title) {
                Label(message, systemImage: icon).foregroundStyle(color)
                HStack(spacing: 24) {
                    count(summary.copied, "copiadas")
                    count(summary.alreadyThere, "ya estaban")
                    count(summary.failures.count, "con problemas")
                }
                if !summary.failures.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(summary.failures.prefix(10), id: \.name) { failure in
                            Text("\(failure.name): \(Self.describe(failure.problem))").font(.caption)
                        }
                        if summary.failures.count > 10 {
                            Text("y \(summary.failures.count - 10) más").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = session.ejectError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
            }
            Toggle("Expulsar la tarjeta al terminar", isOn: $session.ejectWhenDone)
            HStack {
                if let folder = session.destinationFolder {
                    Button("Mostrar en el Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                }
                // Solo si la tarjeta descargada sigue ahí (si en su ranura hay ya otra, esa es la siguiente).
                if session.diskMonitor.disks.contains(where: { $0.id == session.finishedDiskID }), session.nextCard?.id != session.finishedDiskID {
                    Button("Expulsar tarjeta") { session.eject() }
                }
                Spacer()
                if let next = session.nextCard {
                    // Otra tarjeta ya metida: se descarga con los mismos ajustes, sin volver a las opciones.
                    Button("Descargar \(next.name)\(nextDetails(next))") { session.downloadNextCard() }
                        .buttonStyle(.borderedProminent)
                    Button("Nueva descarga") { session.reset() }
                } else {
                    Button("Nueva descarga") { session.reset() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func count(_ value: Int, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading) {
            Text(value.formatted()).font(.caobaTitle(32)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// « (Canon · 124,68 GB)».
    private func nextDetails(_ disk: ExternalDisk) -> String {
        let parts = [disk.cameraBrand, CardImportSession.bytes(disk.size)].compactMap { $0 }
        return " (" + parts.joined(separator: " · ") + ")"
    }

    static func describe(_ problem: CardImportSummary.Problem) -> String {
        switch problem {
        case .verificationFailed: return L("la copia no coincide con la de la tarjeta (dos intentos)")
        case .other(let message): return message
        }
    }

    private var title: LocalizedStringKey {
        switch summary.ending {
        case .completed: return summary.failures.isEmpty ? "Descarga terminada" : "Terminada con problemas"
        case .cancelled: return "Cancelada"
        case .cardRemoved: return "Tarjeta desconectada"
        }
    }

    private var message: String {
        switch summary.ending {
        case .completed:
            return summary.failures.isEmpty
                ? L("Todo copiado y comprobado.")
                : L("Algunas fotos no se han podido copiar. Vuelve a descargar para reintentarlo: lo ya copiado se salta.")
        case .cancelled:
            return L("Has parado la descarga. Lo copiado está a salvo; vuelve a descargar para seguir.")
        case .cardRemoved:
            return L("La tarjeta ha desaparecido a mitad. Lo copiado está a salvo; vuelve a meterla y descarga para seguir.")
        }
    }

    private var icon: String {
        summary.ending == .completed && summary.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var color: Color {
        summary.ending == .completed && summary.failures.isEmpty ? .green : .orange
    }
}
