using WnacgDownloader.Core;

var mode = args.FirstOrDefault() ?? "proxy";
var port = int.Parse(args.ElementAtOrDefault(1) ?? "7890");
var settings = new AppSettings
{
    NetworkMode = mode.Equals("doh", StringComparison.OrdinalIgnoreCase)
        ? NetworkMode.Doh
        : NetworkMode.SystemProxy,
    UseCustomProxyPort = !mode.Equals("doh", StringComparison.OrdinalIgnoreCase),
    ProxyPort = port,
    DownloadDirectory = Path.Combine(Path.GetTempPath(), "wnacg-smoke"),
};

Console.WriteLine($"mode={settings.NetworkMode} port={settings.ProxyPort}");
using var client = new WnacgClient(settings);

var preview = await client.GetPreviewAsync(
    "https://www.wnacg.com/photos-index-aid-383877.html"
);
Console.WriteLine(
    $"TITLE={preview.Title}\nPAGES={preview.Pages}\nCOVER={preview.CoverUrl}\n" +
    $"CATEGORY={preview.Category}\nTAGS={string.Join(",", preview.Tags)}\n" +
    $"UPLOADER={preview.Uploader}"
);

var pageUrls = await client.GetPageUrlsAsync(preview.Aid);
Console.WriteLine($"PAGE_IMAGES={pageUrls.Count}\nFIRST={pageUrls.FirstOrDefault()}");

var bytes = await client.GetBytesAsync(pageUrls[0], preview.PageUrl);
Console.WriteLine($"FIRST_IMAGE_BYTES={bytes.Length}");

var bookmarks = BookmarkParser.ParseText(
    $"<a href=\"{preview.PageUrl}\">{preview.Title}</a>\n" +
    "https://www.wnacg.com/photos-index-aid-123456.html\n"
);
Console.WriteLine($"BOOKMARKS={bookmarks.Count}");
foreach (var bookmark in bookmarks)
{
    Console.WriteLine($"  {bookmark.Aid} | {bookmark.Title} | {bookmark.Url}");
}

if (args.Contains("download"))
{
    Console.WriteLine("DOWNLOAD_START");
    var lastPercent = -1;
    var downloader = new DownloadService(client);
    var folder = await downloader.DownloadAsync(
        preview,
        settings,
        new Progress<DownloadProgress>(p =>
        {
            var percent = p.Total > 0 ? (int)(p.Fraction * 100) : 0;
            if (percent != lastPercent && (percent % 10 == 0 || p.Done == p.Total))
            {
                lastPercent = percent;
                Console.WriteLine($"  {percent}% {p.Status} ({p.Done}/{p.Total})");
            }
        })
    );
    Console.WriteLine($"DOWNLOADED={folder}");
    Console.WriteLine($"FILES={Directory.GetFiles(folder).Length}");

    var pdf = Path.Combine(
        Path.GetDirectoryName(folder)!,
        Path.GetFileName(folder) + ".pdf"
    );
    if (File.Exists(pdf))
    {
        Console.WriteLine($"PDF_BYTES={new FileInfo(pdf).Length}");
        Console.WriteLine($"PDF_PAGES={PdfBuilder.CountPages(pdf)}");
        Console.WriteLine($"PDF_VALID={PdfBuilder.LooksLikeValidPdf(pdf)}");
    }
    else
    {
        Console.WriteLine("PDF_MISSING");
    }
}

Console.WriteLine("SMOKE_OK");
