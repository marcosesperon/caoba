import SwiftUI
import CaobaCore

/// Registro de cambios por versión, leído del `CHANGELOG.md` incluido en la app.
struct Changelog {
    struct Section: Identifiable, Equatable {
        var version: String
        var date: String?
        var lines: [String]
        var id: String { version }
    }

    var sections: [Section]

    /// Lee el fichero del paquete; si falta, no hay novedades que enseñar.
    static func bundled() -> Changelog {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return Changelog(sections: []) }
        return parse(text)
    }

    /// Formato: `## versión — fecha` seguido de viñetas `- …`. Lo demás se ignora.
    static func parse(_ text: String) -> Changelog {
        var sections: [Section] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                let header = line.dropFirst(3)
                let parts = header.components(separatedBy: " — ")
                sections.append(Section(version: parts[0].trimmingCharacters(in: .whitespaces), date: parts.count > 1 ? parts[1] : nil, lines: []))
            } else if line.hasPrefix("- "), !sections.isEmpty {
                sections[sections.count - 1].lines.append(String(line.dropFirst(2)))
            }
        }
        return Changelog(sections: sections)
    }

    /// Secciones posteriores a `lastSeen` hasta `current`, de la más nueva a la más antigua.
    func sections(after lastSeen: String, upTo current: String) -> [Section] {
        sections.filter { VersionCheck.isNewer($0.version, than: lastSeen) && !VersionCheck.isNewer($0.version, than: current) }
    }
}

/// Hoja «Novedades»: las secciones que toque, con las viñetas en negrita donde el changelog las marca.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sections: [Changelog.Section]
    let title: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                Text(title).font(.caobaTitle(20))
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Versión \(section.version)").font(.headline)
                                if let date = section.date { Text(date).font(.caption).foregroundStyle(.secondary) }
                            }
                            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(Color.accentColor)
                                    Text(Self.markdown(line)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Entendido") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 520, height: 460)
    }

    /// Negritas `**así**` del changelog; si algo no parsea, texto plano.
    private static func markdown(_ line: String) -> AttributedString {
        (try? AttributedString(markdown: line, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line)
    }
}
