import SwiftUI

struct CategoryEditorView: View {
    @ObservedObject var store: VaultViewModel
    let context: CategoryEditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var nameIsFocused: Bool

    init(store: VaultViewModel, context: CategoryEditorContext) {
        self.store = store
        self.context = context
        _name = State(initialValue: context.categoryID.flatMap(store.category(id:))?.name ?? "")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(context.categoryID == nil ? "新建分类" : "重命名分类")
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 7) {
                Text("分类名称")
                    .font(.system(size: 12, weight: .semibold))
                TextField("例如：常用账号", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameIsFocused)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    store.saveCategory(id: context.categoryID, name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(22)
        .frame(width: 360)
        .quickVaultGlass(cornerRadius: 18)
        .onAppear {
            DispatchQueue.main.async {
                nameIsFocused = true
            }
        }
    }
}
