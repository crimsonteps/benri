import SwiftUI

struct CategoryEditorView: View {
    @ObservedObject var store: VaultViewModel
    let context: CategoryEditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedIconName: String
    @FocusState private var nameIsFocused: Bool

    init(store: VaultViewModel, context: CategoryEditorContext) {
        self.store = store
        self.context = context
        let category = context.categoryID.flatMap(store.category(id:))
        _name = State(initialValue: category?.name ?? "")
        _selectedIconName = State(
            initialValue: category.map(CategoryIconCatalog.iconName(for:)) ?? "folder"
        )
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("分类名称", text: $name)
                .textFieldStyle(.plain)
                .focused($nameIsFocused)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(36), spacing: 8),
                    count: 7
                ),
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(CategoryIconCatalog.options) { option in
                    Button {
                        selectedIconName = option.name
                    } label: {
                        Image(systemName: option.name)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 34, height: 32)
                            .background(
                                selectedIconName == option.name
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selectedIconName == option.name
                                            ? Color.accentColor.opacity(0.7)
                                            : Color.primary.opacity(0.08),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(option.label)
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    store.saveCategory(
                        id: context.categoryID,
                        name: name,
                        iconName: selectedIconName
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 380)
        .benriGlass(cornerRadius: 18)
        .onAppear {
            DispatchQueue.main.async {
                nameIsFocused = true
            }
        }
    }
}
