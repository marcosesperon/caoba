import Foundation
import Observation
import CaobaCore

/// Los tipos de álbum de Ajustes (las plantillas base de cada álbum). CAOBA no trae ninguno:
/// los crea el usuario. Se guardan en las preferencias, como la estructura de sesiones.
@MainActor
@Observable
final class AlbumTypeStore {
    static let shared = AlbumTypeStore()
    static let key = "caoba.album.types"

    private(set) var types: [AlbumType] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([AlbumType].self, from: data) {
            types = saved
        }
    }

    func type(id: UUID?) -> AlbumType? {
        types.first { $0.id == id }
    }

    /// Tipo nuevo con medidas de partida (30 × 30) y un nombre libre.
    @discardableResult
    func add() -> AlbumType {
        let type = AlbumType(name: uniqueName(L("Álbum nuevo")))
        types.append(type)
        save()
        return type
    }

    @discardableResult
    func duplicate(_ type: AlbumType) -> AlbumType {
        let copy = AlbumType(name: uniqueName(L("\(type.name) copia")), spec: type.spec)
        if let index = types.firstIndex(where: { $0.id == type.id }) {
            types.insert(copy, at: index + 1)
        } else {
            types.append(copy)
        }
        save()
        return copy
    }

    func update(_ type: AlbumType) {
        guard let index = types.firstIndex(where: { $0.id == type.id }), types[index] != type else { return }
        types[index] = type
        save()
    }

    func delete(_ type: AlbumType) {
        types.removeAll { $0.id == type.id }
        save()
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(types.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(types) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
