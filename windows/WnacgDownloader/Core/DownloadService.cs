using System.Diagnostics;
using System.IO.Compression;

namespace WnacgDownloader.Core;

public sealed class DownloadService
{
    private readonly WnacgClient _client;

    public DownloadService(WnacgClient client)
    {
        _client = client;
    }

    public async Task<string> DownloadAsync(
        AlbumPreview album,
        AppSettings settings,
        IProgress<DownloadProgress>? progress = null,
        CancellationToken ct = default
    )
    {
        if (string.IsNullOrWhiteSpace(album.Aid))
        {
            throw new WnacgException("作品信息不完整，无法下载。");
        }

        var baseDir = SettingsStore.Expand(settings.DownloadDirectory);
        Directory.CreateDirectory(baseDir);

        progress?.Report(new DownloadProgress(0, 0, 0, "正在获取图片地址…"));
        var pageUrls = await _client.GetPageUrlsAsync(album.Aid, ct);

        var folderName = HtmlParser.SafeFilename(album.Title);
        var targetDir = UniqueDirectory(baseDir, folderName);
        Directory.CreateDirectory(targetDir);

        var total = pageUrls.Count;
        var done = 0;
        long bytes = 0;
        var gate = new SemaphoreSlim(Math.Clamp(settings.ImageConcurrency, 1, 12));
        var tasks = new List<Task>(total);

        for (var index = 0; index < pageUrls.Count; index++)
        {
            var pageIndex = index;
            var url = pageUrls[index];
            tasks.Add(
                Task.Run(
                    async () =>
                    {
                        await gate.WaitAsync(ct);
                        try
                        {
                            var data = await _client.GetBytesAsync(
                                url,
                                album.PageUrl,
                                ct
                            );
                            var ext = HtmlParser.GuessImageExtension(url);
                            var file = Path.Combine(
                                targetDir,
                                $"{pageIndex + 1:D3}{ext}"
                            );
                            await File.WriteAllBytesAsync(file, data, ct);

                            var finished = Interlocked.Increment(ref done);
                            Interlocked.Add(ref bytes, data.Length);
                            progress?.Report(
                                new DownloadProgress(
                                    finished,
                                    total,
                                    Interlocked.Read(ref bytes),
                                    $"下载中 {finished}/{total}"
                                )
                            );
                        }
                        finally
                        {
                            gate.Release();
                        }
                    },
                    ct
                )
            );
        }

        await Task.WhenAll(tasks);

        try
        {
            var info = Path.Combine(targetDir, "info.txt");
            var lines = new List<string>
            {
                $"标题：{album.Title}",
                $"aid：{album.Aid}",
                $"页面：{album.PageUrl}",
            };
            if (album.Pages is int pages) lines.Add($"页数：{pages}");
            if (!string.IsNullOrWhiteSpace(album.Category)) lines.Add($"分类：{album.Category}");
            if (album.Tags.Count > 0) lines.Add($"标签：{string.Join(", ", album.Tags)}");
            if (!string.IsNullOrWhiteSpace(album.Uploader)) lines.Add($"上传者：{album.Uploader}");
            File.WriteAllLines(info, lines);
        }
        catch
        {
            // info.txt is a convenience, never fail the download for it.
        }

        if (settings.CreateZip)
        {
            progress?.Report(
                new DownloadProgress(total, total, Interlocked.Read(ref bytes), "正在打包 ZIP…")
            );
            var zipPath = Path.Combine(baseDir, folderName + ".zip");
            if (File.Exists(zipPath))
            {
                File.Delete(zipPath);
            }

            await Task.Run(
                () =>
                    ZipFile.CreateFromDirectory(
                        targetDir,
                        zipPath,
                        CompressionLevel.Fastest,
                        includeBaseDirectory: false
                    ),
                ct
            );
        }

        progress?.Report(
            new DownloadProgress(total, total, Interlocked.Read(ref bytes), "下载完成")
        );
        return targetDir;
    }

    public Task OpenFolderAsync(string path)
    {
        if (Directory.Exists(path))
        {
            Process.Start(
                new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = $"\"{path}\"",
                    UseShellExecute = true,
                }
            );
        }

        return Task.CompletedTask;
    }

    private static string UniqueDirectory(string baseDir, string name)
    {
        var candidate = Path.Combine(baseDir, name);
        if (!Directory.Exists(candidate))
        {
            return candidate;
        }

        var suffix = 2;
        while (true)
        {
            candidate = Path.Combine(baseDir, $"{name} ({suffix})");
            if (!Directory.Exists(candidate))
            {
                return candidate;
            }

            suffix++;
        }
    }
}
