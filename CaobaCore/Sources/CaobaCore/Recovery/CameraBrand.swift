import Foundation

/// Adivina la marca de la cámara que usó una tarjeta mirando los nombres de las carpetas
/// de `DCIM`. Es solo una pista para reconocer la tarjeta en la lista: no abre ninguna foto.
///
/// Las cámaras siguen la norma DCF: carpetas `NNNXXXXX` (tres cifras y cinco caracteres
/// libres), y cada marca suele poner algo suyo en esos cinco caracteres (`100CANON`,
/// `100MSDCF`…). Las Canon modernas ponen el modelo (`100EOSR6`) y además crean `CANONMSC`.
public enum CameraBrand {

    /// Marca y fragmentos que la delatan, en el orden en que se prueban.
    /// Solo la de Canon (`100EOSR6`, `CANONMSC`) está comprobada con una tarjeta real.
    private static let rules: [(brand: String, prefixes: [String])] = [
        ("Canon", ["CANON", "EOS"]),
        ("Nikon", ["NIKON", "NCZ_", "ND"]),
        ("Sony", ["MSDCF"]),
        ("Fujifilm", ["_FUJI"]),
        ("OM System", ["OMSYS", "OLYMP"]),
        ("Panasonic", ["_PANA"]),
        ("Pentax", ["PENTX"]),
        ("Ricoh", ["RICOH"]),
        ("Leica", ["LEICA"]),
        ("GoPro", ["GOPRO"]),
    ]

    /// La marca que más carpetas reconoce, o `nil` si ninguna. Recibe solo los nombres
    /// (`["100EOSR6", "CANONMSC"]`), sin rutas.
    public static func detect(dcimFolders: [String]) -> String? {
        var votes: [String: Int] = [:]
        for folder in dcimFolders {
            if let brand = brand(of: folder) { votes[brand, default: 0] += 1 }
        }
        // Con empate gana la que va antes en `rules`, para que el resultado no dependa del azar.
        return rules.map(\.brand).filter { votes[$0] != nil }.max { votes[$0]! < votes[$1]! }
    }

    /// Marca de una carpeta: en las DCF se mira lo que va tras las tres cifras; en el resto,
    /// el nombre entero (para carpetas auxiliares como `CANONMSC`).
    private static func brand(of folder: String) -> String? {
        let name = folder.uppercased()
        let isDCF = name.count == 8 && name.prefix(3).allSatisfy(\.isNumber)
        let tag = isDCF ? String(name.dropFirst(3)) : name
        return rules.first { rule in rule.prefixes.contains { tag.hasPrefix($0) } }?.brand
    }
}
