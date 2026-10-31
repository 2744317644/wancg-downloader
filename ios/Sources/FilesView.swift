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
    @AppStorage("files.hideZIP") private var hideZIP = false

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    ContentUnavailableView(
                        "还没有下载文件",
                        systemImage: "folder",
                        description: Text("在“下载”页完成 ZIP / PDF 后会出现在这里")
                    )
                } else {
                    List {
                        ForEach(files) { file in
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
                NavigationStack {
                    PDFKitView(url: item.url)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle(item.url.lastPathComponent)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("完成") { preview = nil }
                            }
                        }
                }
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
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            files = []
            return
        }
        files = urls
            .filter { url in
                let ext = url.pathExtension.lowercased()
                guard ext == "zip" || ext == "pdf" else { return false }
                return !(hideZIP && ext == "zip")
            }
            .map(DownloadedFile.init(url:))
            .sorted { $0.date > $1.date }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: files[index].url)
        }
        load()
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
