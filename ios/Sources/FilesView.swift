import PDFKit
import SwiftUI

extension Notification.Name {
    static let downloadsChanged = Notification.Name("wnacg.downloadsChanged")
}

private struct DownloadedFile: Identifiable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
    var size: Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
    var date: Date {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ) else { return .distantPast }
        return (attributes[.modificationDate] as? Date) ?? .distantPast
    }
}

private struct PDFItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct FilesView: View {
    @State private var files: [DownloadedFile] = []
    @State private var preview: PDFItem?
    @State private var searchText = ""
    @AppStorage("files.hideZIP") private var hideZIP = false

    private var visibleFiles: [DownloadedFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { file in
            guard !(hideZIP && !file.isPDF) else { return false }
            guard !query.isEmpty else { return true }
            return file.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView(
                        "还没有下载文件",
                        systemImage: "folder",
                        description: Text("在“下载”页完成 ZIP / PDF 后会出现在这里")
                    )
                } else if visibleFiles.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的文件",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词试试")
                    )
                } else {
                    List {
                        ForEach(visibleFiles) { file in
                            row(file)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("文件")
            .navigationBarTitleDisplayMode(.inline)
            .seamlessNavigationBar()
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索文件"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("隐藏 ZIP 文件", isOn: $hideZIP)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onChange(of: hideZIP) { _, _ in
                load()
            }
            .sheet(item: $preview) { item in
                PDFPreviewView(url: item.url)
            }
            .onAppear(perform: load)
            .onReceive(
                NotificationCenter.default.publisher(for: .downloadsChanged)
            ) { _ in
                load()
            }
        }
    }

    private func row(_ file: DownloadedFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.isPDF ? "doc.richtext.fill" : "doc.zipper")
                .font(.title3)
                .foregroundStyle(file.isPDF ? .red : .blue)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(
                        fromByteCount: file.size, countStyle: .file
                    ))
                    Text(file.date, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if file.isPDF {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ShareLink(item: file.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if file.isPDF {
                preview = PDFItem(url: file.url)
            }
        }
    }

    private func load() {
        files = DownloadFolders.allFiles()
            .map(DownloadedFile.init(url:))
            .sorted { $0.date > $1.date }
    }

    private func delete(at offsets: IndexSet) {
        let targets = visibleFiles
        for index in offsets.sorted(by: >) where targets.indices.contains(index) {
            try? FileManager.default.removeItem(at: targets[index].url)
        }
        load()
    }
}

@MainActor
private final class PDFEditorModel: ObservableObject {
    let url: URL
    let document: PDFDocument?
    @Published var currentPageIndex = 0
    @Published private(set) var pageCount = 0
    @Published var errorMessage: String?

    init(url: URL) {
        self.url = url
        let document = PDFDocument(url: url)
        self.document = document
        pageCount = document?.pageCount ?? 0
    }

    func deleteCurrentPage() -> Bool {
        guard let document, document.pageCount > 1,
              currentPageIndex >= 0,
              currentPageIndex < document.pageCount else {
            errorMessage = "当前 PDF 只剩一页，不能删除。"
            return false
        }

        document.removePage(at: currentPageIndex)
        pageCount = document.pageCount
        currentPageIndex = min(currentPageIndex, pageCount - 1)

        guard let data = document.dataRepresentation() else {
            errorMessage = "无法重新生成 PDF 数据。"
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private struct PDFPreviewView: View {
    let url: URL
    @StateObject private var model: PDFEditorModel
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.url = url
        _model = StateObject(wrappedValue: PDFEditorModel(url: url))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let document = model.document {
                    PDFKitView(
                        document: document,
                        currentPageIndex: $model.currentPageIndex
                    )
                    .id(model.pageCount)
                    .ignoresSafeArea(edges: .bottom)
                    .safeAreaInset(edge: .bottom) {
                        if isEditing, model.pageCount > 0 {
                            editBar
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "无法打开 PDF",
                        systemImage: "doc.richtext",
                        description: Text("文件可能已损坏")
                    )
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "完成编辑" : "编辑") {
                        isEditing.toggle()
                    }
                    .disabled(model.document == nil || model.pageCount == 0)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("删除当前页？", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if model.deleteCurrentPage() {
                        NotificationCenter.default.post(
                            name: .downloadsChanged, object: nil
                        )
                    }
                }
            } message: {
                Text("第 \(model.currentPageIndex + 1) 页，共 \(model.pageCount) 页")
            }
            .alert(
                "编辑失败",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var editBar: some View {
        HStack(spacing: 14) {
            Button {
                model.currentPageIndex = max(0, model.currentPageIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.currentPageIndex == 0)

            Text("第 \(model.currentPageIndex + 1) / \(model.pageCount) 页")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 88)

            Button {
                model.currentPageIndex = min(
                    model.pageCount - 1, model.currentPageIndex + 1
                )
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.currentPageIndex >= model.pageCount - 1)

            Spacer(minLength: 4)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("删除本页", systemImage: "trash")
            }
            .disabled(model.pageCount <= 1)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1)
        view.document = document
        context.coordinator.observe(view)
        showCurrentPage(in: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        if view.document !== document {
            view.document = document
        }
        showCurrentPage(in: view)
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    private func showCurrentPage(in view: PDFView) {
        guard document.pageCount > 0 else { return }
        let index = min(max(0, currentPageIndex), document.pageCount - 1)
        guard let page = document.page(at: index),
              view.currentPage !== page else { return }
        view.go(to: page)
    }

    final class Coordinator: NSObject {
        var parent: PDFKitView

        init(_ parent: PDFKitView) {
            self.parent = parent
        }

        func observe(_ view: PDFView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: view
            )
        }

        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let document = view.document else {
                return
            }
            let index = document.index(for: page)
            guard index != parent.currentPageIndex else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.currentPageIndex = index
            }
        }
    }
}
