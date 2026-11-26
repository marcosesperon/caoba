import SwiftUI
import CaobaCore

/// Medidas y opciones de un álbum. Lo usan los tipos de Ajustes y los ajustes de cada álbum
/// (que empiezan con una copia de las de su tipo).
struct AlbumSpecForm: View {
    @Binding var spec: AlbumSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledRow("Página cerrada") {
                HStack(spacing: 6) {
                    number(cm: $spec.pageWidthMM)
                    Text("×")
                    number(cm: $spec.pageHeightMM)
                    Text("cm").foregroundStyle(.secondary)
                }
            }
            LabeledRow("Sangrado") { mm($spec.bleedMM, help: "Lo que se corta: la imagen crece esto por fuera.") }
            LabeledRow("Seguridad") { mm($spec.safetyMM, help: "Margen por dentro que las fotos no invaden.") }
            LabeledRow("Franja del lomo") { mm($spec.spineMM, help: "A cada lado del lomo: ahí no deben quedar caras.") }
            LabeledRow("Pliegos") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle("Fijar número", isOn: Binding(
                            get: { spec.spreads != nil },
                            set: { spec.spreads = $0 ? (spec.spreads ?? 10) : nil }))
                        if let count = spec.spreads {
                            Stepper("\(count)", value: Binding(get: { count }, set: { spec.spreads = $0 }), in: 1...200)
                                .fixedSize()
                        }
                    }
                    Text(spec.spreads == nil
                         ? "Sin número, el reparto automático añade los pliegos que hagan falta."
                         : "El reparto automático reparte las fotos entre estos pliegos.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledRow("Resolución") {
                HStack {
                    Stepper("\(spec.ppi) ppp", value: $spec.ppi, in: AlbumSpec.ppiRange, step: 50).fixedSize()
                    Text(pixelsText).font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledRow("Primero y último") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("De una sola página", isOn: $spec.singleFirstLast)
                    if spec.singleFirstLast {
                        Picker("Exportar como", selection: $spec.singlePageExport) {
                            Text("Pliego entero").tag(AlbumSinglePageExport.fullSpread)
                            Text("Solo la página útil").tag(AlbumSinglePageExport.pageOnly)
                        }
                        .fixedSize()
                    }
                    Text("El primero solo usa la página derecha y el último solo la izquierda; la otra va pegada a la tapa. Al exportar, el pliego entero con esa mitad en blanco o solo la página útil, según pida el laboratorio.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledRow("Portada") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Con portada", isOn: Binding(
                        get: { spec.cover != nil },
                        set: { spec.cover = $0 ? (spec.cover ?? AlbumCover(widthMM: spec.pageWidthMM + 10, heightMM: spec.pageHeightMM + 10)) : nil }))
                    if spec.cover != nil {
                        coverFields
                    }
                    Text("Contraportada, lomo y tapa en una sola pieza, que se maqueta aparte y se exporta como 00.jpg.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            AlbumSpecPreview(spec: spec)
                .frame(height: 120)
            if !spec.isValid {
                Label("Revisa las medidas: la página tiene que medir al menos 5 cm y los márgenes tienen que dejar sitio.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var coverFields: some View {
        let cover = Binding(get: { spec.cover ?? AlbumCover() }, set: { spec.cover = $0 })
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("Cada tapa").foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    number(mm: cover.widthMM)
                    Text("×")
                    number(mm: cover.heightMM)
                    Text("mm").foregroundStyle(.secondary)
                }
            }
            GridRow {
                Text("Lomo").foregroundStyle(.secondary)
                HStack(spacing: 6) { number(mm: cover.spineWidthMM); Text("mm").foregroundStyle(.secondary) }
            }
            GridRow {
                Text("Sangrado o solapa").foregroundStyle(.secondary)
                HStack(spacing: 6) { number(mm: cover.bleedMM); Text("mm").foregroundStyle(.secondary) }
            }
        }
        .font(.callout)
    }

    /// «7157 × 3614 px por pliego».
    private var pixelsText: String {
        let size = spec.exportPixelSize
        return L("\(size.width) × \(size.height) px por pliego")
    }

    private func mm(_ value: Binding<Double>, help: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            number(mm: value)
            Text("mm").foregroundStyle(.secondary)
            Text(help).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Campo en cm para un valor guardado en mm.
    private func number(cm value: Binding<Double>) -> some View {
        TextField("", value: Binding(get: { value.wrappedValue / 10 }, set: { value.wrappedValue = max(0, $0) * 10 }),
                  format: .number.precision(.fractionLength(0...1)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 56)
    }

    private func number(mm value: Binding<Double>) -> some View {
        TextField("", value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = max(0, $0) }),
                  format: .number.precision(.fractionLength(0...1)))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 56)
    }
}

/// Dibujo pequeño del pliego abierto con sus tres zonas: sangrado (por fuera, rayado), margen
/// de seguridad (línea discontinua) y franja del lomo (sombreada en el centro).
struct AlbumSpecPreview: View {
    let spec: AlbumSpec

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let bleed = spec.bleedMM
                let full = CGSize(width: spec.spreadSize.width + bleed * 2, height: spec.spreadSize.height + bleed * 2)
                let scale = min(geo.size.width / max(full.width, 1), geo.size.height / max(full.height, 1))
                let origin = CGPoint(x: (geo.size.width - full.width * scale) / 2, y: (geo.size.height - full.height * scale) / 2)
                // De mm del corte a puntos de la vista.
                let map = { (r: CGRect) -> CGRect in
                    CGRect(x: origin.x + (r.minX + bleed) * scale, y: origin.y + (r.minY + bleed) * scale,
                           width: r.width * scale, height: r.height * scale)
                }
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.orange.opacity(0.25))
                        .frame(width: full.width * scale, height: full.height * scale)
                        .offset(x: origin.x, y: origin.y)
                    let trim = map(CGRect(origin: .zero, size: spec.spreadSize))
                    Rectangle().fill(Color.white).frame(width: trim.width, height: trim.height).offset(x: trim.minX, y: trim.minY)
                    let strip = map(spec.spineStrip)
                    Rectangle().fill(Color.red.opacity(0.15)).frame(width: strip.width, height: strip.height).offset(x: strip.minX, y: strip.minY)
                    ForEach([AlbumPageSide.left, .right], id: \.self) { side in
                        let content = map(spec.pageContent(side))
                        Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: content.width, height: content.height).offset(x: content.minX, y: content.minY)
                    }
                    Rectangle().fill(Color.secondary).frame(width: 1, height: trim.height)
                        .offset(x: trim.midX, y: trim.minY)
                    Rectangle().stroke(Color.secondary, lineWidth: 1)
                        .frame(width: trim.width, height: trim.height).offset(x: trim.minX, y: trim.minY)
                }
            }
            Text(L("Abierto: \(Self.cm(spec.spreadSize.width)) × \(Self.cm(spec.spreadSize.height)) cm, más el sangrado"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }

    static func cm(_ mm: Double) -> String {
        (mm / 10).formatted(.number.precision(.fractionLength(0...1)))
    }
}
