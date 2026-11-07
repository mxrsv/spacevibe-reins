import Foundation

/// One value of a filter field: the id the state keeps, the line in the menu and the text of the chip.
struct FilterValue: Equatable, Sendable {
    let id: String
    let title: String
    let chip: String

    init(_ id: String, _ title: String, chip: String? = nil) {
        self.id = id
        self.title = title
        self.chip = chip ?? title
    }
}

/// A page's filter fields, in menu order (Skills, Subagents): each lists its values.
protocol FilterFieldKind: Hashable, CaseIterable, Sendable {
    var values: [FilterValue] { get }
}

/// The applied filters of a page: a set of value ids per field. AND across fields, OR within one.
struct PickFilter<Field: FilterFieldKind>: Equatable, Sendable {
    private(set) var picks: [Field: Set<String>] = [:]

    var isOn: Bool { picks.values.contains { !$0.isEmpty } }

    func count(_ field: Field) -> Int { picks[field]?.count ?? 0 }

    func isPicked(_ field: Field, _ value: String) -> Bool { picks[field]?.contains(value) ?? false }

    mutating func toggle(_ field: Field, _ value: String) {
        var set = picks[field] ?? []
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        picks[field] = set.isEmpty ? nil : set
    }

    mutating func clear() { picks = [:] }

    /// The chips in field order, then menu order.
    var chips: [(field: Field, value: FilterValue)] {
        Field.allCases.flatMap { field in
            field.values.filter { isPicked(field, $0.id) }.map { (field, $0) }
        }
    }
}
