import QuickVaultCore
import SwiftUI

struct RecordEditorView: View {
    @ObservedObject var store: VaultViewModel
    let context: RecordEditorContext

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedCategoryID: UUID
    @State private var fields: [RecordField]
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

        let existingFields = existing?.fields.sorted(by: { $0.sortOrder < $1.sortOrder }) ?? []
        _fields = State(
            initialValue: existingFields.isEmpty
                ? [RecordField(label: "", value: "")]
                : existingFields
        )
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
                VStack(alignment: .leading, spacing: 3) {
                    Text(isEditing ? "编辑记录" : "新建记录")
                        .font(.system(size: 18, weight: .bold))
                    Text("每个字段都可以单独复制")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("记录名称")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("例如：公司服务器", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameIsFocused)
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

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("字段")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button {
                                fields.append(
                                    RecordField(
                                        label: "",
                                        value: "",
                                        sortOrder: fields.count
                                    )
                                )
                            } label: {
                                Label("添加字段", systemImage: "plus")
                            }
                            .buttonStyle(.link)
                        }

                        ForEach($fields) { field in
                            FieldEditorRow(field: field) {
                                fields.removeAll(where: { $0.id == field.wrappedValue.id })
                                if fields.isEmpty {
                                    fields.append(RecordField(label: "", value: ""))
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

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
                        fields: fields
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 600, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.async {
                nameIsFocused = true
            }
        }
    }
}

private struct FieldEditorRow: View {
    @Binding var field: RecordField
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("字段名称")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：手机号", text: $field.label)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(isOn: $field.isSensitive) {
                    Label("敏感字段", systemImage: "eye.slash")
                        .font(.system(size: 11, weight: .medium))
                }
                .toggleStyle(.checkbox)
                .fixedSize()

                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("删除字段")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("内容")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if field.isSensitive {
                    SecureField("输入敏感内容", text: $field.value)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("输入内容", text: $field.value)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}
