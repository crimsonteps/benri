import Foundation

public enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
}

public struct ClipboardItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ClipboardItemKind
    public let text: String?
    public let imagePath: String?
    public let createdAt: Date
    public let sourceBundleID: String?
    public let pinnedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: ClipboardItemKind,
        text: String? = nil,
        imagePath: String? = nil,
        createdAt: Date = Date(),
        sourceBundleID: String? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.sourceBundleID = sourceBundleID
        self.pinnedAt = pinnedAt
    }

    public var isPinned: Bool { pinnedAt != nil }

    public func replacing(createdAt: Date? = nil, pinnedAt: Date?) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            text: text,
            imagePath: imagePath,
            createdAt: createdAt ?? self.createdAt,
            sourceBundleID: sourceBundleID,
            pinnedAt: pinnedAt
        )
    }
}

public enum ClipboardRetention: Int, CaseIterable, Identifiable, Sendable {
    case threeHours = -3
    case day = 1
    case week = 7
    case month = 30
    case threeMonths = 90
    case sixMonths = 180
    case year = 365
    case forever = -1

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .threeHours: "3 小时"
        case .day: "1 天"
        case .week: "7 天"
        case .month: "30 天"
        case .threeMonths: "90 天"
        case .sixMonths: "180 天"
        case .year: "1 年"
        case .forever: "永久"
        }
    }

    public var maxAge: TimeInterval {
        switch self {
        case .threeHours: 3 * 3_600
        case .forever: .greatestFiniteMagnitude
        default: TimeInterval(rawValue) * 86_400
        }
    }
}
