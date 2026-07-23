import BenriCore

struct CategoryIconOption: Identifiable {
    let name: String
    let label: String

    var id: String { name }
}

enum CategoryIconCatalog {
    static let options: [CategoryIconOption] = [
        CategoryIconOption(name: "person.crop.circle", label: "个人"),
        CategoryIconOption(name: "person.2", label: "团队"),
        CategoryIconOption(name: "briefcase", label: "工作"),
        CategoryIconOption(name: "building.2", label: "公司"),
        CategoryIconOption(name: "house", label: "家庭"),
        CategoryIconOption(name: "key", label: "密钥"),
        CategoryIconOption(name: "lock", label: "安全"),
        CategoryIconOption(name: "creditcard", label: "卡片"),
        CategoryIconOption(name: "banknote", label: "财务"),
        CategoryIconOption(name: "server.rack", label: "服务器"),
        CategoryIconOption(name: "desktopcomputer", label: "电脑"),
        CategoryIconOption(name: "network", label: "网络"),
        CategoryIconOption(name: "globe", label: "网站"),
        CategoryIconOption(name: "phone", label: "电话"),
        CategoryIconOption(name: "envelope", label: "邮件"),
        CategoryIconOption(name: "doc.text", label: "文档"),
        CategoryIconOption(name: "bookmark", label: "收藏"),
        CategoryIconOption(name: "star", label: "重要"),
        CategoryIconOption(name: "tray", label: "其他"),
        CategoryIconOption(name: "folder", label: "文件夹")
    ]

    static func iconName(for category: VaultCategory) -> String {
        category.iconName
            ?? VaultDefaults.categories.first(where: { $0.id == category.id })?.iconName
            ?? "folder"
    }
}
