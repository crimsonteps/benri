import Foundation

public enum VaultContentType: String, Codable, Sendable {
    case text
    case account
    case password
    case phone
    case email
    case url
    case bash
    case json

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = VaultContentType(rawValue: rawValue) ?? .text
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct VaultRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var categoryID: UUID
    public var content: String
    public var contentType: VaultContentType
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        categoryID: UUID,
        content: String = "",
        contentType: VaultContentType = .text,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryID = categoryID
        self.content = content
        self.contentType = contentType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case categoryID
        case content
        case contentType
        case fields
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        categoryID = try container.decode(UUID.self, forKey: .categoryID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        contentType = try container.decodeIfPresent(VaultContentType.self, forKey: .contentType) ?? .text

        if let currentContent = try container.decodeIfPresent(String.self, forKey: .content) {
            content = currentContent
        } else {
            let legacyFields = try container.decodeIfPresent([LegacyRecordField].self, forKey: .fields) ?? []
            content = legacyFields
                .sorted { $0.sortOrder < $1.sortOrder }
                .compactMap(\.mergedText)
                .joined(separator: "\n")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(content, forKey: .content)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct LegacyRecordField: Decodable {
    var label: String
    var value: String
    var sortOrder: Int

    private enum CodingKeys: String, CodingKey {
        case label
        case value
        case sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    var mergedText: String? {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanLabel.isEmpty {
            return value.isEmpty ? nil : value
        }
        if value.isEmpty {
            return cleanLabel
        }
        return "\(cleanLabel): \(value)"
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

public enum VaultPayloadError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedFormat(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(version):
            return "当前版本无法读取格式版本为 \(version) 的保险库。"
        }
    }
}

public struct VaultPayload: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 3

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

    private enum CodingKeys: String, CodingKey {
        case formatVersion
        case categories
        case records
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFormatVersion = try container.decode(Int.self, forKey: .formatVersion)
        guard decodedFormatVersion <= VaultPayload.currentFormatVersion else {
            throw VaultPayloadError.unsupportedFormat(decodedFormatVersion)
        }

        formatVersion = decodedFormatVersion
        categories = try container.decode([VaultCategory].self, forKey: .categories)
        records = try container.decode([VaultRecord].self, forKey: .records)
    }

    public func encode(to encoder: Encoder) throws {
        guard formatVersion <= VaultPayload.currentFormatVersion else {
            throw VaultPayloadError.unsupportedFormat(formatVersion)
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(categories, forKey: .categories)
        try container.encode(records, forKey: .records)
    }

    public static var empty: VaultPayload {
        VaultPayload()
    }

    public func categoryName(for id: UUID) -> String {
        categories.first(where: { $0.id == id })?.name ?? "其他"
    }

    @discardableResult
    public mutating func migrateToCurrentFormat() -> Bool {
        guard formatVersion <= VaultPayload.currentFormatVersion else { return false }

        let existingCategoryIDs = Set(categories.map(\.id))
        let missingBuiltInCategories = VaultDefaults.categories.filter { category in
            !existingCategoryIDs.contains(category.id)
        }
        let requiresVersionMigration = formatVersion < VaultPayload.currentFormatVersion

        categories.append(contentsOf: missingBuiltInCategories)
        if requiresVersionMigration {
            formatVersion = VaultPayload.currentFormatVersion
        }

        return requiresVersionMigration || !missingBuiltInCategories.isEmpty
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
