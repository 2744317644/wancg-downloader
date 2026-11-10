import SwiftUI

/// Manage the tags/keywords that should be hidden from listing screens.
/// Stored as newline-separated text in `@AppStorage`.
struct TagExclusionSheet: View {
    @Binding var rawTags: String
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var tags: [String] {
        TagExclusionStore.list(from: rawTags)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        TextField("输入标签或关键词", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($inputFocused)
                            .onSubmit(add)
                        Button("添加", action: add)
                            .disabled(trimmedInput.isEmpty)
                    }
                } footer: {
                    Text("例如 NTR、触手、AI。列表会按站点标签页精确排除；索引尚未覆盖时按标题关键词回退。")
                }

                Section("已排除的标签") {
                    if tags.isEmpty {
                        Text("还没有排除标签")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button {
                                    remove(tag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("取消排除 \(tag)")
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("排除标签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let value = trimmedInput
        guard !value.isEmpty else { return }
        var current = tags
        if !TagExclusionStore.contains(value, in: current) {
            current.append(value)
            rawTags = TagExclusionStore.serialize(current)
        }
        input = ""
        inputFocused = true
    }

    private func remove(_ tag: String) {
        var current = tags
        current.removeAll { $0 == tag }
        rawTags = TagExclusionStore.serialize(current)
    }

    private func delete(at offsets: IndexSet) {
        var current = tags
        current.remove(atOffsets: offsets)
        rawTags = TagExclusionStore.serialize(current)
    }
}
