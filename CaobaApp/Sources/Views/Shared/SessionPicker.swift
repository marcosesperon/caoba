import SwiftUI
import CaobaCore

/// Selector de la sesión activa, en el sitio del título de la ventana: el nombre de la sesión
/// con su fecha debajo, o «CAOBA» si no hay. Al pulsarlo sale la lista de sesiones de la
/// carpeta raíz con buscador, «Nueva sesión…» y «Sin sesión». En las herramientas que no van
/// con una sesión (QR, Shutter Count…) es solo el texto «CAOBA»: la sesión sigue activa por debajo.
struct SessionPicker: View {
    @Environment(AppState.self) private var appState
    @State private var showList = false
    @State private var showNew = false
    @State private var hovering = false

    private var sessions: StudioSessions { appState.sessions }

    var body: some View {
        if appState.currentModule.usesSession {
            picker
        } else {
            Text(verbatim: "CAOBA").font(.headline)
                .padding(.horizontal, 6).padding(.vertical, 2)
        }
    }

    private var picker: some View {
        Button {
            sessions.refresh()
            showList = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                // Como el título de la ventana: nombre en negrita y la fecha debajo, pequeña.
                VStack(alignment: .leading, spacing: 0) {
                    Text(appState.activeSession?.name ?? "CAOBA")
                        .font(.headline)
                        .lineLimit(1).truncationMode(.tail)
                    if let active = appState.activeSession {
                        Text(sessions.layout.dateText(active.date))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            // Fondo suave solo al pasar el ratón, para que se note que se puede pulsar.
            .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .frame(maxWidth: 360, alignment: .leading)
        .help(appState.activeSession?.folder.path ?? String(localized: "Elige la sesión con la que trabajas: los módulos saldrán con su origen y su destino."))
        .onAppear {
            // Para capturas: `--state sessions.list=1` abre la lista y `sessions.new=1` la hoja de nueva sesión.
            if appState.launchState["sessions.list"] != nil { showList = true }
            if appState.launchState["sessions.new"] != nil { showNew = true }
            openRequestedList()
        }
        // Ventana nueva de ⌘N: sale con la lista desplegada para elegir sesión.
        .onChange(of: appState.requestSessionList) { openRequestedList() }
        .popover(isPresented: $showList, arrowEdge: .bottom) {
            SessionList(showNew: $showNew, dismiss: { showList = false })
                .environment(appState)
        }
        .sheet(isPresented: $showNew) {
            NewSessionSheet().environment(appState)
        }
    }

    private func openRequestedList() {
        guard appState.requestSessionList else { return }
        appState.requestSessionList = false
        sessions.refresh()
        showList = true
    }
}

/// Lista de sesiones del selector (también la abre «Elegir sesión…» de la barra de origen).
struct SessionList: View {
    @Environment(AppState.self) private var appState
    @Binding var showNew: Bool
    let dismiss: () -> Void
    @State private var search = ""

    private var sessions: StudioSessions { appState.sessions }

    /// Busca en el nombre de la carpeta, sin distinguir mayúsculas ni acentos.
    private var filtered: [StudioSession] {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return sessions.list }
        return sessions.list.filter { $0.title.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sessions.layout.root == nil {
                Text("Para usar sesiones, elige primero en Ajustes › Sesiones la carpeta donde las guardas.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsLink { Text("Abrir Ajustes…") }
            } else {
                TextField("Buscar", text: $search)
                    .textFieldStyle(.roundedBorder)
                if filtered.isEmpty {
                    Text(sessions.list.isEmpty ? "No hay sesiones en la carpeta raíz." : "Ninguna sesión coincide.")
                        .foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filtered) { session in row(session) }
                        }
                    }
                    .frame(height: min(CGFloat(filtered.count) * 26, 320))
                }
                Divider()
                HStack {
                    Button("Nueva sesión…") {
                        dismiss()
                        showNew = true
                    }
                    Spacer()
                    Button("Sin sesión") {
                        Task { await appState.activateSession(nil) }
                        dismiss()
                    }
                    .disabled(appState.activeSession == nil)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func row(_ session: StudioSession) -> some View {
        SessionRow(session: session,
                   isActive: session.id == appState.activeSession?.id,
                   isOpenElsewhere: appState.app.isSessionOpen(session, besides: appState),
                   dismiss: dismiss)
    }
}

/// Una sesión de la lista. El clic la pone en esta ventana; al pasar el ratón sale el botón para
/// abrirla en una ventana nueva. Si otra ventana ya la tiene, sale en gris y no se puede elegir.
private struct SessionRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    let session: StudioSession
    let isActive: Bool
    let isOpenElsewhere: Bool
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                Task { await appState.activateSession(session) }
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "checkmark").opacity(isActive ? 1 : 0).foregroundStyle(Color.accentColor)
                    Text(session.title).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if isOpenElsewhere {
                        Text("En otra ventana").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4).padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isOpenElsewhere)
            // Ni la de esta ventana ni la que ya está en otra: no tendría sentido abrirlas aparte.
            if hovering && !isActive && !isOpenElsewhere {
                Button {
                    openWindow(value: WindowSeed(sessionPath: session.folder.path, module: appState.currentModule.rawValue))
                    dismiss()
                } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Abrir en ventana nueva")
            }
        }
        .onHover { hovering = $0 }
        .help(isOpenElsewhere ? String(localized: "Ya está abierta en otra ventana.") : session.folder.path)
    }
}

/// «Nueva sesión»: fecha (hoy por defecto) y nombre; crea las carpetas y la deja activa.
struct NewSessionSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var name = ""
    @State private var error: String?
    private let createTitle: LocalizedStringKey
    /// Lo que se hace con la sesión ya creada y activa (p. ej. empezar a descargar la tarjeta).
    private let onCreated: (() -> Void)?

    init(date: Date = Date(), createTitle: LocalizedStringKey = "Crear", onCreated: (() -> Void)? = nil) {
        _date = State(initialValue: date)
        self.createTitle = createTitle
        self.onCreated = onCreated
    }

    private var layout: SessionLayout { appState.sessions.layout }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nueva sesión").font(.headline)
            Form {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                TextField("Nombre", text: $name, prompt: Text("Nombre de la sesión"))
            }
            // Cómo quedará en disco, para que no haya sorpresas.
            if let folder = layout.sessionFolder(date: date, name: cleanName.isEmpty ? "…" : cleanName) {
                VStack(alignment: .leading, spacing: 2) {
                    // Recortada por el principio: lo que importa es el final (año y sesión).
                    Text(folder.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.head)
                    Text("Con las carpetas: \(layout.subfolders.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Elige antes la carpeta raíz de sesiones en Ajustes.").foregroundStyle(.orange)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(createTitle) { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanName.isEmpty || layout.root == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func create() {
        do {
            let session = try appState.sessions.create(date: date, name: cleanName)
            Task {
                await appState.activateSession(session)
                onCreated?()
            }
            dismiss()
        } catch {
            self.error = JobRunner.describe(error)
        }
    }
}
