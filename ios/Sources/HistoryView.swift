import SwiftUI

private struct HistorySection: Identifiable {
    let date: Date
    let items: [HistoryEntry]

    var id: Date { date }
}

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var showClearConfirm = false
    @State private var searchText = ""
    var embedded = false

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [HistoryEntry] {
        guard !query.isEmpty else { return history.items }
        return history.items.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.aid.contains(query)
        }
    }

    private var noMatches: Bool {
        !history.items.isEmpty && filteredItems.isEmpty
    }

    private var sections: [HistorySection] {
        Dictionary(grouping: filteredItems) { entry in
            Calendar.current.startOfDay(for: entry.viewedAt)
        }
        .map { date, entries in
            HistorySection(
                date: date,
                items: entries.sorted { $0.viewedAt > $1.viewedAt }
            )
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
                if history.items.isEmpty {
                    ContentUnavailableView(
                        "还没有浏览记录",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("在首页点进漫画详情后才会记录")
                    )
                } else if noMatches {
                    ContentUnavailableView(
                        "没有匹配的历史",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词试试")
                    )
                } else {
                    List {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.items) { entry in
                                    NavigationLink {
                                        AlbumDetailView(album: entry.homeAlbum)
                                    } label: {
                                        row(entry)
                                    }
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            history.remove(entry)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(sectionTitle(section.date))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("历史")
            .navigationBarTitleDisplayMode(.inline)
            .seamlessNavigationBar()
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索历史"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(history.items.isEmpty)
                }
            }
            .alert("清空历史记录？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    history.clear()
                }
            } message: {
                Text("清空后无法恢复，但不会删除已下载的文件。")
            }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            HomeCover(album: entry.homeAlbum)
                .frame(width: 54, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let pages = entry.pages {
                        Text("\(pages)P")
                    }
                    Text(entry.viewedAt, format: .dateTime.hour().minute())
                    Text(entry.viewedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func sectionTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(
            .dateTime.year().month().day().weekday(.abbreviated)
        )
    }
}
