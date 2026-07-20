import Foundation

public struct RecordField: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String
    public var isSensitive: Bool
    public var sortOrder: Int

    public init(
        id: UUID = UUID(),
        label: String,
        value: String,
        isSensitive: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.isSensitive = isSensitive
        self.sortOrder = sortOrder
    }
}

public struct VaultRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryID: UUID
    public var fields: [RecordField]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        categoryID: UUID,
        fields: [RecordField] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.fields = fields
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VaultCategory: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isBuiltIn = isBuiltIn
    }
}

public enum VaultDefaults {
    public static let personalCategoryID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public static let workCategoryID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    public static let serverCategoryID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    public static let otherCategoryID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!

    public static let categories: [VaultCategory] = [
        VaultCategory(id: personalCategoryID, name: "个人", sortOrder: 0, isBuiltIn: true),
        VaultCategory(id: workCategoryID, name: "工作", sortOrder: 1, isBuiltIn: true),
        VaultCategory(id: serverCategoryID, name: "服务器", sortOrder: 2, isBuiltIn: true),
        VaultCategory(id: otherCategoryID, name: "其他", sortOrder: 3, isBuiltIn: true)
    ]
}

public struct VaultPayload: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var categories: [VaultCategory]
    public var records: [VaultRecord]

    public init(
        formatVersion: Int = VaultPayload.currentFormatVersion,
        categories: [VaultCategory] = VaultDefaults.categories,
        records: [VaultRecord] = []
    ) {
        self.formatVersion = formatVersion
        self.categories = categories
        self.records = records
    }

    public static var empty: VaultPayload {
        VaultPayload()
    }

    public func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "其他"
    }

    public func filteredRecords(categoryID: UUID?, query: String) -> [VaultRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return records
            .filter { record in
                let categoryMatches = categoryID == nil || record.categoryID == categoryID
                let queryMatches = trimmedQuery.isEmpty
                    || record.name.localizedCaseInsensitiveContains(trimmedQuery)
                return categoryMatches && queryMatches
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    public mutating func deleteCustomCategory(id: UUID) {
        guard let category = categories.first(where: { $0.id == id }), !category.isBuiltIn else {
            return
        }

        categories.removeAll(where: { $0.id == id })
        for index in records.indices where records[index].categoryID == id {
            records[index].categoryID = VaultDefaults.otherCategoryID
            records[index].updatedAt = Date()
        }
    }
}
