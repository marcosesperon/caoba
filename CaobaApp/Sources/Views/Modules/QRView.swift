import SwiftUI
import CaobaCore

/// Generador de códigos QR con nueve tipos de contenido y vista previa en vivo.
struct QRView: View {
    enum ContentType: String, CaseIterable, Identifiable {
        case text, url, wifi, vcard, email, phone, sms, geo, event
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .text: return "Texto"
            case .url: return "URL"
            case .wifi: return "WiFi"
            case .vcard: return "Contacto"
            case .email: return "Email"
            case .phone: return "Teléfono"
            case .sms: return "SMS"
            case .geo: return "Ubicación"
            case .event: return "Evento"
            }
        }
    }

    @State private var type: ContentType = .url
    @State private var text = ""
    @State private var wifiSSID = ""
    @State private var wifiPassword = ""
    @State private var wifiSecurity: QRContent.WifiSecurity = .wpa
    @State private var wifiHidden = false
    @State private var vName = ""
    @State private var vOrg = ""
    @State private var vTitle = ""
    @State private var vPhone = ""
    @State private var vEmail = ""
    @State private var vWeb = ""
    @State private var vAddress = ""
    @State private var emailTo = ""
    @State private var emailSubject = ""
    @State private var emailBody = ""
    @State private var phone = ""
    @State private var smsNumber = ""
    @State private var smsBody = ""
    @State private var geoLat = 42.8805
    @State private var geoLon = -8.5456
    @State private var eventTitle = ""
    @State private var eventLocation = ""
    @State private var eventStart = Date()
    @State private var eventHasEnd = false
    @State private var eventEnd = Date().addingTimeInterval(3600)

    @State private var size = 512
    @State private var foreground = Color.black
    @State private var background = Color.white
    @State private var correction: QROptions.ErrorCorrection = .medium
    @State private var margin = 2
    @State private var logoURL: URL?
    @State private var logoPercent = 20
    @State private var preview: CGImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var errorText: String?

    private var content: QRContent {
        switch type {
        case .text: return .text(text)
        case .url: return .url(text)
        case .wifi: return .wifi(ssid: wifiSSID, password: wifiPassword, security: wifiSecurity, hidden: wifiHidden)
        case .vcard: return .vcard(name: vName, organization: vOrg, title: vTitle, phone: vPhone, email: vEmail, website: vWeb, address: vAddress)
        case .email: return .email(to: emailTo, subject: emailSubject, body: emailBody)
        case .phone: return .phone(phone)
        case .sms: return .sms(number: smsNumber, message: smsBody)
        case .geo: return .geo(latitude: geoLat, longitude: geoLon)
        case .event: return .event(title: eventTitle, location: eventLocation, start: eventStart, end: eventHasEnd ? eventEnd : nil)
        }
    }

    private var options: QROptions {
        // Con logo subimos la corrección a Q como mínimo, para que siga leyéndose.
        var level = correction
        if logoURL != nil, level == .low || level == .medium { level = .quartile }
        return QROptions(size: size, foreground: CaobaCore.RGBColor(foreground), background: CaobaCore.RGBColor(background),
                         correction: level, marginModules: margin, logoPercent: logoPercent)
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleTitle(title: "Código QR")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledRow("Tipo") {
                            Picker("", selection: $type) {
                                ForEach(ContentType.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                        }
                        OptionGroup(title: "Contenido") { contentForm }
                        OptionGroup(title: "Aspecto") {
                            LabeledRow("Tamaño") {
                                Picker("", selection: $size) {
                                    ForEach([256, 512, 1024, 2048], id: \.self) { Text("\($0) px").tag($0) }
                                }
                                .labelsHidden()
                            }
                            LabeledRow("Color") {
                                ColorPicker("", selection: $foreground, supportsOpacity: false).labelsHidden()
                                Text("Fondo").foregroundStyle(.secondary).padding(.leading, 12)
                                ColorPicker("", selection: $background, supportsOpacity: false).labelsHidden()
                            }
                            LabeledRow("Corrección de errores") {
                                Picker("", selection: $correction) {
                                    Text("L (7 %)").tag(QROptions.ErrorCorrection.low)
                                    Text("M (15 %)").tag(QROptions.ErrorCorrection.medium)
                                    Text("Q (25 %)").tag(QROptions.ErrorCorrection.quartile)
                                    Text("H (30 %)").tag(QROptions.ErrorCorrection.high)
                                }
                                .labelsHidden()
                            }
                            LabeledRow("Margen") { Stepper("\(margin) módulos", value: $margin, in: 0...10).fixedSize() }
                            HStack {
                                Text(logoURL?.lastPathComponent ?? String(localized: "Sin logo"))
                                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                Button("Elegir logo…") { chooseLogo() }
                                if logoURL != nil { Button("Quitar") { logoURL = nil } }
                            }
                            if logoURL != nil {
                                LabeledRow("Tamaño del logo") { Stepper("\(logoPercent) %", value: $logoPercent, in: 5...40, step: 5).fixedSize() }
                            }
                        }
                    }
                }
                Spacer()
                HStack {
                    if let errorText { Text(errorText).foregroundStyle(.red).font(.callout) }
                    Spacer()
                    Button("Guardar PNG…") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(preview == nil)
                }
            }
            .padding(.trailing, 8)
            .frame(minWidth: 360, idealWidth: 420)

            VStack {
                if let preview {
                    Image(decorative: preview, scale: 1).resizable().interpolation(.none).scaledToFit()
                        .padding(20)
                } else {
                    ContentUnavailableView("Completa los datos", systemImage: "qrcode", description: Text("La vista previa aparece en cuanto haya contenido."))
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: content) { schedulePreview() }
        .onChange(of: options) { schedulePreview() }
        .onAppear { schedulePreview() }
    }

    @ViewBuilder
    private var contentForm: some View {
        switch type {
        case .text:
            TextField("Texto", text: $text, axis: .vertical).lineLimit(3...6)
        case .url:
            TextField("https://…", text: $text)
        case .wifi:
            TextField("Nombre de la red (SSID)", text: $wifiSSID)
            SecureField("Contraseña", text: $wifiPassword)
            LabeledRow("Seguridad") {
                Picker("", selection: $wifiSecurity) {
                    Text("WPA/WPA2").tag(QRContent.WifiSecurity.wpa)
                    Text("WEP").tag(QRContent.WifiSecurity.wep)
                    Text("Sin contraseña").tag(QRContent.WifiSecurity.none)
                }
                .labelsHidden()
            }
            Toggle("Red oculta", isOn: $wifiHidden)
        case .vcard:
            TextField("Nombre completo", text: $vName)
            TextField("Empresa", text: $vOrg)
            TextField("Cargo", text: $vTitle)
            TextField("Teléfono", text: $vPhone)
            TextField("Email", text: $vEmail)
            TextField("Web", text: $vWeb)
            TextField("Dirección", text: $vAddress)
        case .email:
            TextField("Destinatario", text: $emailTo)
            TextField("Asunto", text: $emailSubject)
            TextField("Mensaje", text: $emailBody, axis: .vertical).lineLimit(2...5)
        case .phone:
            TextField("Número de teléfono", text: $phone)
        case .sms:
            TextField("Número", text: $smsNumber)
            TextField("Mensaje", text: $smsBody, axis: .vertical).lineLimit(2...4)
        case .geo:
            TextField("Latitud", value: $geoLat, format: .number)
            TextField("Longitud", value: $geoLon, format: .number)
        case .event:
            TextField("Título", text: $eventTitle)
            TextField("Lugar", text: $eventLocation)
            DatePicker("Inicio", selection: $eventStart)
            Toggle("Con fin", isOn: $eventHasEnd)
            if eventHasEnd { DatePicker("Fin", selection: $eventEnd) }
        }
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        if panel.runModal() == .OK { logoURL = panel.url }
    }

    private func schedulePreview() {
        previewTask?.cancel()
        let payload = content.payload
        let opts = options
        let logo = logoURL
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { preview = nil; errorText = nil; return }
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let result: Result<CGImage, Error> = await Task.detached {
                do {
                    let logoImage = try logo.map { try ImageIOHelpers.loadImage(from: $0) }
                    return .success(try QRGenerator.make(text: payload, options: opts, logo: logoImage))
                } catch { return .failure(error) }
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let image): preview = image; errorText = nil
            case .failure(let error): preview = nil; errorText = JobRunner.describe(error)
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "qr-code.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let payload = content.payload
        let opts = options
        let logo = logoURL
        Task.detached {
            do {
                let logoImage = try logo.map { try ImageIOHelpers.loadImage(from: $0) }
                let data = try QRGenerator.png(text: payload, options: opts, logo: logoImage)
                try data.write(to: url)
            } catch {
                await MainActor.run { errorText = JobRunner.describe(error) }
            }
        }
    }
}

extension CaobaCore.RGBColor {
    /// Convierte un color de SwiftUI a nuestro RGB sencillo (en sRGB).
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent))
    }
}
