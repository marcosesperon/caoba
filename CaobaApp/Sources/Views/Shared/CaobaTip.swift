import SwiftUI

// Tooltip propio de CAOBA: un globo con el rojo de la app que sale enseguida (0,3 s) encima del
// botón. El de macOS tarda alrededor de un segundo y no se puede cambiar de color.
//
// Se usa en dos partes:
// - `.caobaTip(texto)` en cada botón: avisa cuando el ratón entra o sale y cuenta dónde está.
// - `.caobaTipHost()` en la zona que los contiene: dibuja un único globo para todos, encima del
//   botón que toca y sin salirse por los lados. Va por fuera de cualquier recorte (p. ej. después
//   de `.caobaPanel`), porque el globo cae fuera de la zona.

/// Qué globo se ve en una zona, y los tiempos para que salga o se vaya.
@MainActor @Observable
final class CaobaTipState {
    /// Lo que tarda en salir el globo al dejar el ratón encima.
    static let delay: Duration = .milliseconds(300)
    /// Margen al salir de un botón: si en ese rato se entra en otro, su globo sale al momento.
    static let grace: Duration = .milliseconds(150)

    /// El botón cuyo globo se ve, y su texto.
    private(set) var shownID: String?
    private(set) var text: Text?

    /// Globos pedidos a la fuerza (capturas de prueba). Se guardan todos porque una misma vista
    /// puede estar repetida (p. ej. `ViewThatFits` prepara dos diseños y solo enseña uno): sale el
    /// del botón que de verdad se ve.
    private var forced: [String: Text] = [:]
    private var pendingID: String?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// El ratón entra en un botón: si ya había un globo a la vista, se cambia al momento; si no,
    /// sale tras el retraso.
    func enter(_ id: String, text: Text) {
        hideTask?.cancel()
        showTask?.cancel()
        if shownID != nil {
            show(id, text: text)
            return
        }
        pendingID = id
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.show(id, text: text)
        }
    }

    /// El ratón sale de un botón: se quita su globo (con un pequeño margen por si va al de al lado).
    func leave(_ id: String) {
        if pendingID == id {
            showTask?.cancel()
            pendingID = nil
        }
        guard shownID == id else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.grace)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Para las capturas de prueba: el globo de este botón, a la vista sin pasar el ratón.
    func force(_ id: String, text: Text) {
        forced[id] = text
    }

    /// El globo que toca dibujar, entre los botones que se ven (`visible`).
    func current(in visible: Set<String>) -> (id: String, text: Text)? {
        if let shownID, let text, visible.contains(shownID) { return (shownID, text) }
        return forced.first { visible.contains($0.key) }.map { ($0.key, $0.value) }
    }

    /// Lo enseña ya, sin esperar.
    func show(_ id: String, text: Text) {
        pendingID = nil
        shownID = id
        self.text = text
    }

    /// Lo quita ya (al pulsar el botón, por ejemplo).
    func hide() {
        showTask?.cancel()
        hideTask?.cancel()
        pendingID = nil
        shownID = nil
        text = nil
        forced = [:]
    }
}

/// Dónde está cada botón con globo, para que la zona sepa dónde dibujarlo.
private struct CaobaTipAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Lo que se pone en cada botón.
private struct CaobaTipModifier: ViewModifier {
    let text: Text
    /// Para las capturas de prueba: el globo sale nada más aparecer.
    let showNow: Bool
    @Environment(CaobaTipState.self) private var tips: CaobaTipState?
    // Cada botón tiene su id; si la vista se repite (p. ej. al medir dos diseños), cada copia el suyo.
    @State private var id = UUID().uuidString

    func body(content: Content) -> some View {
        if let tips {
            content
                .onHover { inside in inside ? tips.enter(id, text: text) : tips.leave(id) }
                .simultaneousGesture(TapGesture().onEnded { tips.hide() })
                .anchorPreference(key: CaobaTipAnchors.self, value: .bounds) { [id: $0] }
                .accessibilityHint(text)
                .onAppear { if showNow { tips.force(id, text: text) } }
                .onDisappear { tips.leave(id) }
        } else {
            // Fuera de una zona con globo, el tooltip de siempre.
            content.help(text)
        }
    }
}

/// Lo que se pone en la zona: dibuja el globo del botón que toca.
private struct CaobaTipHostModifier: ViewModifier {
    @State private var tips = CaobaTipState()

    func body(content: Content) -> some View {
        content
            .environment(tips)
            .overlayPreferenceValue(CaobaTipAnchors.self) { anchors in
                GeometryReader { proxy in
                    if let tip = tips.current(in: Set(anchors.keys)), let anchor = anchors[tip.id] {
                        let button = proxy[anchor]
                        let width = proxy.size.width
                        CaobaTipBubble(text: tip.text)
                            // Centrado encima del botón, pero sin salirse por los lados de la zona.
                            .alignmentGuide(.leading) { size in
                                let x = min(max(button.midX - size.width / 2, 0), max(width - size.width, 0))
                                return -x
                            }
                            .alignmentGuide(.top) { size in -(button.minY - size.height - 6) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.opacity)
                    }
                }
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.12), value: tips.shownID)
            }
    }
}

/// El globo: rojo de la app, texto blanco, como mucho `maxWidth` de ancho (si no cabe, varias líneas).
private struct CaobaTipBubble: View {
    let text: Text
    static let maxWidth: CGFloat = 320

    var body: some View {
        CaobaTipWidth(maxWidth: Self.maxWidth) {
            text
                .font(.callout)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

/// Mide el texto: si cabe en una línea dentro de `maxWidth`, ocupa lo justo; si no, `maxWidth`
/// y las líneas que hagan falta.
private struct CaobaTipWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let ideal = text.sizeThatFits(.unspecified)
        return ideal.width <= maxWidth ? ideal : text.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

extension View {
    /// Globo rojo de CAOBA con este texto al dejar el ratón encima. Hace falta un `.caobaTipHost()`
    /// por encima; sin él, se queda con el tooltip de macOS.
    func caobaTip(_ text: Text, showNow: Bool = false) -> some View {
        modifier(CaobaTipModifier(text: text, showNow: showNow))
    }

    func caobaTip(_ key: LocalizedStringKey, showNow: Bool = false) -> some View {
        caobaTip(Text(key), showNow: showNow)
    }

    func caobaTip(verbatim string: String, showNow: Bool = false) -> some View {
        caobaTip(Text(verbatim: string), showNow: showNow)
    }

    /// Zona donde se dibujan los globos de los `.caobaTip` que tiene dentro.
    func caobaTipHost() -> some View {
        modifier(CaobaTipHostModifier())
    }
}
