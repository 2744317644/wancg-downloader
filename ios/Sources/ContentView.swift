import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var downloads: DownloadHistory
    @State private var showAlreadyDownloaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        inputCard
                        if let preview = model.preview {
                            previewCard(preview)
                        }
                        if let error = model.errorMessage {
                            errorCard(error)
                        }
                        statusBar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .alert("已经下载过", isPresented: $showAlreadyDownloaded) {
                Button("取消", role: .cancel) {}
                Button("重新下载", role: .destructive) {
                    Task { await model.download() }
                }
            } message: {
                Text("这部作品已经下载过。重新下载会覆盖同名文件。")
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                ]
                : [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("作品链接")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.9))

            TextField(
                "https://www.wnacg.com/photos-index-aid-383877.html",
                text: $model.input,
                axis: .vertical
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .lineLimit(1...3)
            .padding(12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Button {
                Task { await model.parse() }
            } label: {
                HStack {
                    if model.isBusy && model.preview == nil {
                        ProgressView().tint(.black)
                    }
                    Text(model.isBusy && model.preview == nil ? "解析中…" : "解析作品")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .foregroundStyle(.black)
            .disabled(model.isBusy)

            Text("也支持直接输入编号，例如 383877")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func previewCard(_ preview: MangaPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let image = model.coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.primary.opacity(0.05)
                            ProgressView()
                        }
                    }
                }
                .frame(width: 104, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(4)

                    if !preview.category.isEmpty {
                        Text(preview.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if let pages = preview.pages {
                            Label("\(pages)P", systemImage: "doc.text")
                        }
                        if let favorites = preview.favorites {
                            Label("\(favorites)", systemImage: "heart")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !preview.uploader.isEmpty {
                        Text("@\(preview.uploader)")
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
                    }
                }
                Spacer(minLength: 0)
            }

            if !preview.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(preview.tags.prefix(8), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                                .foregroundStyle(.blue.opacity(0.9))
                        }
                    }
                }
            }

            Link(destination: preview.pageURL) {
                Label("打开原页", systemImage: "safari")
                    .font(.caption)
            }

            Divider()
                .overlay(Color.primary.opacity(0.06))

            downloadControls
        }
        .padding(16)
        .background(cardBackground)
    }

    private var downloadControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: $model.makePDF) {
                Text("同时生成 PDF（300 DPI / 最高质量）")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.9))
            }
            .tint(.mint)
            .disabled(model.isBusy)

            Button {
                if let preview = model.preview,
                   downloads.isDownloaded(preview.aid)
                    || downloads.hasDownloadedFile(matching: preview.title) {
                    showAlreadyDownloaded = true
                } else {
                    Task { await model.download() }
                }
            } label: {
                HStack {
                    if model.isBusy {
                        ProgressView().tint(.black)
                    }
                    Text(model.isBusy ? "处理中…" : "下载 ZIP" + (model.makePDF ? " + PDF" : ""))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .foregroundStyle(.white)
            .disabled(model.isBusy)

            if model.downloadProgress > 0 {
                progressRow(
                    title: "ZIP",
                    value: model.downloadProgress <= 0.7
                        ? model.downloadProgress / 0.7
                        : 1
                )
            }
            if model.makePDF && model.pdfProgress > 0 {
                progressRow(
                    title: "PDF",
                    value: (model.pdfProgress - 0.7) / 0.3
                )
            }

            if let zipURL = model.zipURL {
                ShareLink(item: zipURL) {
                    Label("保存 / 分享 ZIP", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                }
            }
            if let pdfURL = model.pdfURL {
                ShareLink(item: pdfURL) {
                    Label("保存 / 分享 PDF", systemImage: "doc.richtext")
                        .font(.subheadline)
                }
            }
        }
    }

    private func progressRow(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(max(0, min(1, value)) * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: max(0, min(1, value)))
                .tint(title == "PDF" ? .blue : .mint)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            Text(model.status)
            Spacer()
            if !model.queue.isEmpty {
                Label("队列 \(model.queue.count)", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(Color.red.opacity(0.9))
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView(model: AppModel())
}
