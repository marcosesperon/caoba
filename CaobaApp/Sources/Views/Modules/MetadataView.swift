import SwiftUI
import MapKit
import CaobaCore

/// Metadatos por foto: lista a la izquierda, ficha y formulario a la derecha.
struct MetadataView: View {
    @Environment(AppState.self) private var appState

    enum ApplyMode: String, CaseIterable, Identifiable {
        case single, all
        var id: String { rawValue }
    }

    @State private var selected: URL?
    @State private var current: PhotoMetadata?
    @State private var applyMode: ApplyMode = .single
    @State private var stripOthers = false
    /// Ediciones pendientes por fichero (modo "solo esta foto").
    @State private var edits: [URL: MetadataEdit] = [:]
    @State private var form = FormFields()

    struct FormFields: Equatable {
        var artist = ""
        var copyright = ""
        var description = ""
        var date = ""
        var hasGPS = false
        var latitude = 0.0
        var longitude = 0.0

        var edit: MetadataEdit {
            MetadataEdit(artist: artist, copyright: copyright, description: description, dateTimeOriginal: date,
                         gps: hasGPS ? .some(GPSCoordinate(latitude: latitude, longitude: longitude)) : .some(nil))
        }

        init() {}

        init(from metadata: PhotoMetadata) {
            artist = metadata.artist ?? ""
            copyright = metadata.copyright ?? ""
            description = metadata.description ?? ""
            date = metadata.dateTimeOriginal ?? ""
            if let gps = metadata.gps {
                hasGPS = true
                latitude = gps.latitude
                longitude = gps.longitude
            }
        }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                ModuleTitle(title: "Metadatos")
                // Lista compartida: las casillas definen "todas las marcadas"; el clic elige la ficha.
                FileListView(selection: $selected, markedNames: Set(edits.keys.map(\.lastPathComponent)))
            }
            .frame(minWidth: 340, idealWidth: 420)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let selected, let current {
                        HStack(alignment: .top, spacing: 16) {
                            ThumbnailView(url: selected, maxPixelSize: 400, displaySize: 160)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selected.lastPathComponent).font(.headline)
                                infoRow("Cámara", current.camera)
                                infoRow("Objetivo", current.lens)
                                infoRow("Dimensiones", current.size.map { "\($0.width) × \($0.height)" })
                                infoRow("ISO", current.iso.map(String.init))
                                infoRow("Apertura", current.fNumber.map { "f/\($0.formatted())" })
                                infoRow("Exposición", current.exposureTime.map(formatExposure))
                                infoRow("Focal", current.focalLength.map { "\($0.formatted()) mm" })
                                infoRow("Software", current.software)
                            }
                            Spacer()
                        }
                        if let gps = current.gps {
                            MapSnippet(coordinate: CLLocationCoordinate2D(latitude: gps.latitude, longitude: gps.longitude))
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button("Abrir en Google Maps") {
                                appState.openExternal(URL(string: "https://www.google.com/maps?q=\(gps.latitude),\(gps.longitude)")!)
                            }
                            .buttonStyle(.link)
                        }
                    } else {
                        ContentUnavailableView("Elige una foto", systemImage: "photo", description: Text("Selecciona un archivo de la lista para ver y editar sus metadatos."))
                            .frame(height: 220)
                    }

                    OptionGroup(title: "Editar") {
                        LabeledRow("Aplicar a") {
                            Picker("", selection: $applyMode) {
                                Text("Solo esta foto").tag(ApplyMode.single)
                                Text("Todas las marcadas (\(appState.checkedCount))").tag(ApplyMode.all)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        TextField("Artista", text: $form.artist)
                        TextField("Copyright", text: $form.copyright)
                        TextField("Descripción", text: $form.description)
                        TextField("Fecha (AAAA:MM:DD hh:mm:ss)", text: $form.date)
                        Toggle("Coordenadas GPS", isOn: $form.hasGPS)
                        if form.hasGPS {
                            HStack {
                                TextField("Latitud", value: $form.latitude, format: .number)
                                TextField("Longitud", value: $form.longitude, format: .number)
                            }
                        }
                        Toggle("Eliminar el resto de metadatos", isOn: $stripOthers)
                        Text("La imagen no se recomprime: solo cambian los metadatos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        if applyMode == .single {
                            Button("Guardar cambio de esta foto") { stageCurrent() }.disabled(selected == nil)
                            Text("\(edits.count) pendientes").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Escribir metadatos") { run() }
                            .buttonStyle(.borderedProminent)
                            .disabled(applyMode == .single ? edits.isEmpty : appState.checkedFiles.isEmpty)
                    }
                }
                .padding(.leading, 12)
            }
            .frame(minWidth: 420)
        }
        .onChange(of: selected) { load() }
        .onChange(of: appState.files) {
            if selected == nil || !appState.files.contains(where: { $0.url == selected }) {
                selected = appState.files.first?.url
            }
            edits = edits.filter { key, _ in appState.files.contains { $0.url == key } }
        }
        .onAppear { if selected == nil { selected = appState.files.first?.url } }
    }

    private func infoRow(_ label: LocalizedStringKey, _ value: String?) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
            Text(value ?? "—")
        }
        .font(.callout)
    }

    private func formatExposure(_ seconds: Double) -> String {
        if seconds >= 1 { return "\(seconds.formatted()) s" }
        return "1/\(Int((1 / seconds).rounded())) s"
    }

    private func load() {
        guard let url = selected else { current = nil; return }
        Task {
            let metadata = await Task.detached { MetadataService.read(url) }.value
            current = metadata
            form = FormFields(from: metadata)
            // Si ya había un cambio pendiente para esta foto, lo mostramos.
            if let pending = edits[url] {
                form.artist = pending.artist ?? form.artist
                form.copyright = pending.copyright ?? form.copyright
                form.description = pending.description ?? form.description
                form.date = pending.dateTimeOriginal ?? form.date
            }
        }
    }

    /// Guarda en memoria el cambio de la foto actual (modo "solo esta foto").
    private func stageCurrent() {
        guard let url = selected else { return }
        edits[url] = form.edit
    }

    private func run() {
        let strip = stripOthers
        let pairs: [(URL, MetadataEdit)]
        switch applyMode {
        case .single: pairs = edits.map { ($0.key, $0.value) }
        case .all: pairs = appState.checkedFiles.map { ($0, form.edit) }
        }
        appState.jobRunner.run(openURL: appState.sourceFolder) { progress in
            try await MetadataService.writePerFile(pairs, stripOthers: strip, progress: progress)
        }
        Task {
            while appState.jobRunner.isRunning { try? await Task.sleep(for: .milliseconds(200)) }
            edits = [:]
            load()
        }
    }
}

/// Mapa pequeño con el marcador de la foto.
struct MapSnippet: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))) {
            Marker("", coordinate: coordinate)
        }
        .mapControlVisibility(.hidden)
    }
}
