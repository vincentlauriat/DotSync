import Foundation

/// Mirror of `dot status --json` (see ~/.dotfiles/dot, status_data()).
struct DotStatus: Decodable, Equatable {
    struct Problem: Decodable, Equatable, Identifiable {
        let state: String
        let path: String
        var id: String { path }
    }

    struct LastSync: Decodable, Equatable {
        let date: String
        let ok: Bool
        let kind: String
        let message: String

        var parsedDate: Date? { ISO8601DateFormatter().date(from: date) }
    }

    let repo: String
    let host: String
    let problems: [Problem]
    let pendingChanges: Int
    let ahead: Int
    let behind: Int
    let hasRemote: Bool
    let autosync: Bool
    let syncing: Bool
    let lastSync: LastSync?
    let log: String
}

enum Health {
    case ok, syncing, attention, broken

    var symbol: String {
        switch self {
        case .ok: "arrow.triangle.2.circlepath"
        case .syncing: "arrow.triangle.2.circlepath.circle.fill"
        case .attention: "exclamationmark.arrow.triangle.2.circlepath"
        case .broken: "xmark.octagon"
        }
    }
}

extension DotStatus {
    var health: Health {
        if syncing { return .syncing }
        if !problems.isEmpty || lastSync?.ok == false { return .attention }
        return .ok
    }
}
