import Foundation

/// Cuánto hueco sin fotos separa dos sesiones.
public enum CardSessionGap: String, Sendable, Codable, CaseIterable {
    case fifteenMinutes, thirtyMinutes, fortyFiveMinutes
    case oneHour, twoHours, fourHours, eightHours
    /// Una sesión por día natural.
    case byDay

    /// Hueco en segundos; `nil` en «por días».
    public var seconds: TimeInterval? {
        switch self {
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1_800
        case .fortyFiveMinutes: return 2_700
        case .oneHour: return 3_600
        case .twoHours: return 7_200
        case .fourHours: return 14_400
        case .eightHours: return 28_800
        case .byDay: return nil
        }
    }
}

/// Fotos de la tarjeta hechas seguidas: un encargo, un paseo, un día de viaje.
public struct CardSession: Sendable, Equatable, Identifiable {
    public var items: [CardItem]

    public init(items: [CardItem]) {
        self.items = items
    }

    /// La hora de la primera foto identifica la sesión (no cambia al marcar o desmarcar).
    public var id: Date { start }
    public var start: Date { items.first?.file.date ?? .distantPast }
    public var end: Date { items.last?.file.date ?? .distantPast }
    public var totalSize: Int64 { items.reduce(0) { $0 + $1.totalSize } }
    public var urls: Set<URL> { Set(items.map(\.file.url)) }

    /// Unas cuantas fotos repartidas (primera, del medio y última) para reconocer la sesión.
    /// Con 0 no devuelve ninguna y con 1, la primera (antes devolvía todas y desbordaba la tira).
    public func sample(_ count: Int) -> [CardItem] {
        guard count > 1 else { return Array(items.prefix(max(count, 0))) }
        guard items.count > count else { return items }
        let step = Double(items.count - 1) / Double(count - 1)
        return (0..<count).map { items[Int((Double($0) * step).rounded())] }
    }
}

public enum CardSessions {
    /// Agrupa las fotos por hora: una sesión nueva cuando entre una foto y la siguiente pasa
    /// más tiempo que `gap`, o cada día natural con `.byDay`. De la más reciente a la más antigua.
    public static func group(_ items: [CardItem], gap: CardSessionGap, calendar: Calendar = .current) -> [CardSession] {
        let sorted = items.sorted { $0.file.date < $1.file.date }
        var sessions: [[CardItem]] = []
        for item in sorted {
            if let previous = sessions.last?.last, !startsNewSession(item, after: previous, gap: gap, calendar: calendar) {
                sessions[sessions.count - 1].append(item)
            } else {
                sessions.append([item])
            }
        }
        return sessions.reversed().map(CardSession.init(items:))
    }

    private static func startsNewSession(_ item: CardItem, after previous: CardItem, gap: CardSessionGap, calendar: Calendar) -> Bool {
        guard let seconds = gap.seconds else { return !calendar.isDate(item.file.date, inSameDayAs: previous.file.date) }
        return item.file.date.timeIntervalSince(previous.file.date) > seconds
    }
}
