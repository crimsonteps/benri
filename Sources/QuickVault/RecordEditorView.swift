import QuickVaultCore
import SwiftUI

struct RecordEditorView: View {
    @ObservedObject var store: VaultViewModel
    let context: RecordEditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedCategoryID: UUID
    @State private var content: String
    @FocusState private var nameIsFocused: Bool

    init(store: VaultViewModel, context: RecordEditorContext) {
        self.store = store
        self.context = context

        let existing = context.recordID.flatMap(store.record(id:))
        _name = State(initialValue: existing?.name ?? "")
        _selectedCategoryID = State(
            initialValue: existing?.categoryID
                ?? store.selectedCategoryID
                ?? VaultDefaults.personalCategoryID
        )
        _content = State(initialValue: existing?.content ?? "")
    }

    private var isEditing: Bool {
        context.recordID != nil
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isEditing ? "编辑记录" : "新建记录")
                        .font(.system(size: 19, weight: .bold))
                    Text("名称用于搜索，内容可以填写任意文本")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("记录名称")
                        .font(.system(size: 12, weight: .semibold))
                    TextField("例如：公司服务器", text: $name)
                        .textFieldStyle(.plain)
                        .focused($nameIsFocused)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("分类")
                        .font(.system(size: 12, weight: .semibold))
                    Picker("分类", selection: $selectedCategoryID) {
                        ForEach(store.sortedCategories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("内容")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("支持多行文本、网址和账号信息")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    ZStack(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("输入任意内容，例如网址、手机号、账号密码或备注")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $content)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .scrollContentBackground(.hidden)
                            .padding(5)
                    }
                    .frame(minHeight: 140, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity)

            Divider().opacity(0.55)

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    store.saveRecord(
                        id: context.recordID,
                        name: name,
                        categoryID: selectedCategoryID,
                        content: content
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 600, height: 460)
        .quickVaultGlass(cornerRadius: 20)
        .onAppear {
            DispatchQueue.main.async {
                nameIsFocused = true
            }
        }
    }
}
