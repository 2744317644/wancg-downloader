import PDFKit
import SwiftUI

extension Notification.Name {
    static let downloadsChanged = Notification.Name("wnacg.downloadsChanged")
}

private struct DownloadedFile: Identifiable {
    let url: URL
    /// File-system metadata is read once in `init`; previously `date`/`size`
    /// hit the disk on every access, including inside the sort comparator.
    let size: Int64
    let date: Date

    init(url: URL) {
        self.url = url
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        )
        size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        date = (attributes?[.modificationDate] as? Date) ?? .distantPast
    }

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
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
            .background(AppBackground())
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

private let selectionAnnotationMarker = "wnacg.page.selection"

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

    func deletePages(_ indexes: Set<Int>) -> Bool {
        guard let document else {
            errorMessage = "无法打开 PDF。"
            return false
        }
        let valid = indexes.filter {
            $0 >= 0 && $0 < document.pageCount
        }
        guard !valid.isEmpty else { return false }
        guard valid.count < document.pageCount else {
            errorMessage = "不能删除全部页面。"
            return false
        }

        clearSelectionAnnotations()
        for index in valid.sorted(by: >) {
            document.removePage(at: index)
        }
        pageCount = document.pageCount
        currentPageIndex = min(currentPageIndex, max(0, pageCount - 1))

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

    private func clearSelectionAnnotations() {
        guard let document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations
            where annotation.contents == selectionAnnotationMarker {
                page.removeAnnotation(annotation)
            }
        }
    }
}

private struct PDFPreviewView: View {
    let url: URL
    @StateObject private var model: PDFEditorModel
    @State private var isEditing = false
    @State private var selectedPages: Set<Int> = []
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
                        currentPageIndex: $model.currentPageIndex,
                        isEditing: isEditing,
                        selectedPages: $selectedPages
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
                        if !isEditing {
                            selectedPages.removeAll()
                        }
                    }
                    .disabled(model.document == nil || model.pageCount == 0)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("删除选中的页？", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if model.deletePages(selectedPages) {
                        selectedPages.removeAll()
                        NotificationCenter.default.post(
                            name: .downloadsChanged, object: nil
                        )
                    }
                }
            } message: {
                Text(
                    "共 \(selectedPages.count) 页，此操作会直接覆盖保存当前 PDF。"
                )
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
        HStack(spacing: 12) {
            Text(
                selectedPages.isEmpty
                    ? "点击页面选择要删除的页"
                    : "已选 \(selectedPages.count) 页"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            if !selectedPages.isEmpty {
                Button("取消选择") {
                    selectedPages.removeAll()
                }
                .font(.caption)
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("删除选中", systemImage: "trash")
            }
            .font(.subheadline)
            .disabled(selectedPages.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    let isEditing: Bool
    @Binding var selectedPages: Set<Int>

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
        context.coordinator.pdfView = view

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        showCurrentPage(in: view)
        context.coordinator.syncSelection()
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pdfView = view
        if view.document !== document {
            view.document = document
        }
        showCurrentPage(in: view)
        context.coordinator.syncSelection()
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        coordinator.stopObserving()
        coordinator.clearSelectionAnnotations()
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
        weak var pdfView: PDFView?
        private var annotations: [Int: PDFAnnotation] = [:]

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

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard parent.isEditing,
                  let view = pdfView,
                  let document = view.document else {
                return
            }
            let point = gesture.location(in: view)
            guard let page = view.page(for: point, nearest: true) else {
                return
            }
            let index = document.index(for: page)
            guard index >= 0, index < document.pageCount else { return }

            var selection = parent.selectedPages
            if selection.contains(index) {
                selection.remove(index)
                removeAnnotation(for: index)
            } else {
                selection.insert(index)
                addAnnotation(for: index, page: page)
            }
            parent.selectedPages = selection
        }

        func syncSelection() {
            guard let document = pdfView?.document else {
                clearSelectionAnnotations()
                return
            }
            let desired = parent.isEditing ? parent.selectedPages : []

            for index in Array(annotations.keys) where !desired.contains(index) {
                removeAnnotation(for: index)
            }
            for index in desired where annotations[index] == nil {
                guard let page = document.page(at: index) else { continue }
                addAnnotation(for: index, page: page)
            }
        }

        func clearSelectionAnnotations() {
            for index in Array(annotations.keys) {
                removeAnnotation(for: index)
            }
        }

        private func addAnnotation(for index: Int, page: PDFPage) {
            guard annotations[index] == nil else { return }
            let bounds = page.bounds(for: .mediaBox)
            guard !bounds.isEmpty else { return }

            let annotation = PDFAnnotation(
                bounds: bounds,
                forType: .square,
                withProperties: nil
            )
            annotation.color = UIColor.systemMint.withAlphaComponent(0.8)
            annotation.interiorColor = UIColor.systemMint.withAlphaComponent(0.18)
            let border = PDFBorder()
            border.lineWidth = 2
            annotation.border = border
            annotation.contents = selectionAnnotationMarker
            page.addAnnotation(annotation)
            annotations[index] = annotation
        }

        private func removeAnnotation(for index: Int) {
            guard let annotation = annotations.removeValue(forKey: index),
                  let document = pdfView?.document,
                  let page = document.page(at: index) else {
                return
            }
            page.removeAnnotation(annotation)
        }
    }
}
