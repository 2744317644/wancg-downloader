import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var downloads: DownloadHistory
    @State private var showAlreadyDownloaded = false
    @FocusState private var linkFieldFocused: Bool

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
                        if !model.queue.isEmpty {
                            queueCard
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
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .seamlessNavigationBar()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        linkFieldFocused = false
                    }
                }
            }
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
        AppBackground()
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("作品链接")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.9))
                Spacer(minLength: 0)
                Button {
                    if let text = UIPasteboard.general.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !text.isEmpty {
                        model.input = text
                    }
                    linkFieldFocused = true
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .font(.caption.weight(.medium))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.mint)
                .accessibilityLabel("从剪贴板粘贴链接")
            }

            TextField(
                "https://www.wnacg.com/photos-index-aid-383877.html",
                text: $model.input,
                axis: .vertical
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .lineLimit(1...3)
            .focused($linkFieldFocused)
            .padding(12)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Button {
                // Parsing is a point-of-no-return action: drop the keyboard
                // first so the parsed preview and the tab bar are visible
                // immediately instead of being covered by the keyboard.
                linkFieldFocused = false
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

            if model.isBusy {
                downloadProgressCard
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

    private var downloadProgressCard: some View {
        let generatingPDF = model.pdfProgress > 0
        let progress = generatingPDF
            ? min(1, max(0, (model.pdfProgress - 0.7) / 0.3))
            : min(1, max(0, model.downloadProgress / 0.7))
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(generatingPDF ? "正在生成 PDF" : model.status)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if progress > 0 || generatingPDF {
                ProgressView(value: progress)
                    .tint(.blue)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)
            } else {
                ProgressView()
                    .tint(.blue)
            }

            if !generatingPDF, progress > 0 {
                HStack(spacing: 6) {
                    Text("剩余时间 \(etaText)")
                    Spacer()
                    Text(speedText)
                        .foregroundStyle(.blue)
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }

    private var speedText: String {
        guard model.downloadSpeed > 0 else { return "--" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(model.downloadSpeed), countStyle: .file
        ) + "/s"
    }

    private var etaText: String {
        guard let eta = model.downloadETA, eta.isFinite, eta > 0 else {
            return "--:--"
        }
        let total = Int(eta.rounded())
        if total >= 3600 {
            return String(
                format: "%d:%02d:%02d",
                total / 3600, (total % 3600) / 60, total % 60
            )
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("下载队列", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.queue.count) 部")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.queue) { item in
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        UIImpactFeedbackGenerator(style: .light)
                            .impactOccurred()
                        model.cancelQueued(item.aid)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消排队：\(item.title)")
                }
                if item.aid != model.queue.last?.aid {
                    Divider().opacity(0.35)
                }
            }

            Text("当前任务完成后会按顺序自动开始")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(cardBackground)
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
            Button("重试") {
                Task {
                    if model.preview != nil {
                        await model.retryCurrentDownload()
                    } else {
                        await model.parse()
                    }
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.red)
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
