import Foundation

/// Los nueve tipos de contenido del generador de QR. Cada uno sabe convertirse
/// en el texto que se codifica, con los mismos formatos que usaba la app antigua.
public enum QRContent: Sendable, Equatable {
    public enum WifiSecurity: String, Sendable, CaseIterable { case wpa = "WPA", wep = "WEP", none = "nopass" }

    case text(String)
    case url(String)
    case wifi(ssid: String, password: String, security: WifiSecurity, hidden: Bool)
    case vcard(name: String, organization: String, title: String, phone: String, email: String, website: String, address: String)
    case email(to: String, subject: String, body: String)
    case phone(String)
    case sms(number: String, message: String)
    case geo(latitude: Double, longitude: Double)
    case event(title: String, location: String, start: Date, end: Date?)

    /// Texto a codificar. Vacío si faltan los datos obligatorios.
    public var payload: String {
        switch self {
        case .text(let s), .url(let s):
            return s

        case .wifi(let ssid, let password, let security, let hidden):
            let ssid = ssid.trimmingCharacters(in: .whitespaces)
            guard !ssid.isEmpty else { return "" }
            let hiddenPart = hidden ? "H:true;" : ""
            return "WIFI:T:\(security.rawValue);S:\(Self.escapeWifi(ssid));P:\(Self.escapeWifi(password));\(hiddenPart);"

        case .vcard(let name, let organization, let title, let phone, let email, let website, let address):
            let name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return "" }
            let parts = name.split(separator: " ").map(String.init)
            let lastName = parts.count > 1 ? parts.last! : ""
            let firstName = parts.count > 1 ? parts.dropLast().joined(separator: " ") : name
            var lines = ["BEGIN:VCARD", "VERSION:3.0", "N:\(lastName);\(firstName);;;", "FN:\(name)"]
            let org = organization.trimmingCharacters(in: .whitespaces)
            if !org.isEmpty { lines.append("ORG:\(org)") }
            let t = title.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { lines.append("TITLE:\(t)") }
            let p = phone.trimmingCharacters(in: .whitespaces)
            if !p.isEmpty { lines.append("TEL:\(p)") }
            let e = email.trimmingCharacters(in: .whitespaces)
            if !e.isEmpty { lines.append("EMAIL:\(e)") }
            let w = website.trimmingCharacters(in: .whitespaces)
            if !w.isEmpty { lines.append("URL:\(w)") }
            let a = address.trimmingCharacters(in: .whitespaces)
            if !a.isEmpty { lines.append("ADR:;;\(a);;;;") }
            lines.append("END:VCARD")
            return lines.joined(separator: "\n")

        case .email(let to, let subject, let body):
            let to = to.trimmingCharacters(in: .whitespaces)
            guard !to.isEmpty else { return "" }
            var params: [String] = []
            let s = subject.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { params.append("subject=\(Self.encode(s))") }
            let b = body.trimmingCharacters(in: .whitespaces)
            if !b.isEmpty { params.append("body=\(Self.encode(b))") }
            return "mailto:\(to)" + (params.isEmpty ? "" : "?" + params.joined(separator: "&"))

        case .phone(let number):
            let n = number.trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? "" : "tel:\(n)"

        case .sms(let number, let message):
            let n = number.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return "" }
            let m = message.trimmingCharacters(in: .whitespaces)
            return "sms:\(n)" + (m.isEmpty ? "" : "?body=\(Self.encode(m))")

        case .geo(let lat, let lon):
            return "geo:\(Self.coordinate(lat)),\(Self.coordinate(lon))"

        case .event(let title, let location, let start, let end):
            let t = title.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return "" }
            var lines = ["BEGIN:VEVENT", "SUMMARY:\(t)", "DTSTART:\(Self.icsDate(start))"]
            if let end { lines.append("DTEND:\(Self.icsDate(end))") }
            let l = location.trimmingCharacters(in: .whitespaces)
            if !l.isEmpty { lines.append("LOCATION:\(l)") }
            lines.append("END:VEVENT")
            return lines.joined(separator: "\n")
        }
    }

    /// En el formato WIFI hay que escapar `\ ; , : "`.
    static func escapeWifi(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\;,:\"".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// Fecha local en formato iCalendar sin zona: 20240531T142200.
    static func icsDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.string(from: date)
    }
}
