using System.Collections.Concurrent;
using System.Text.RegularExpressions;

namespace WnacgDownloader.Core;

public sealed record BookmarkParseResult(List<BookmarkItem> Items, int RawLinks);

public static class BookmarkParser
{
    private static readonly Regex AidRegex = new(
        "(?:photos-index|photos-item|photos-slide|photos-view|download-index|photos-gallery)-aid-(\\d+)",
        RegexOptions.IgnoreCase | RegexOptions.Compiled
    );

    public static List<BookmarkItem> ParseFile(string path)
    {
        var text = File.ReadAllText(path);
        return ParseText(text);
    }

    /// <summary>
    /// Parse a bookmark export and keep the raw link count so the UI can
    /// explain why the number of downloadable works is lower after
    /// de-duplication.
    /// </summary>
    public static BookmarkParseResult ParseFileWithStats(string path)
    {
        var text = File.ReadAllText(path);
        return new BookmarkParseResult(ParseText(text), AidRegex.Matches(text).Count);
    }

    public static List<BookmarkItem> ParseText(string text)
    {
        var results = new List<BookmarkItem>();
        var byAid = new Dictionary<string, BookmarkItem>();

        void Add(string url, string? title)
        {
            var match = AidRegex.Match(url);
            if (!match.Success)
            {
                return;
            }

            var aid = match.Groups[1].Value;
            if (byAid.TryGetValue(aid, out var existing))
            {
                if (string.IsNullOrWhiteSpace(existing.Title) && !string.IsNullOrWhiteSpace(title))
                {
                    existing.Title = HtmlParser.Clean(title);
                }
                return;
            }

            var item = new BookmarkItem
            {
                Aid = aid,
                Title = string.IsNullOrWhiteSpace(title) ? "" : HtmlParser.Clean(title),
                Url = HtmlParser.NormalizeUrl(url)
                    ?? $"https://www.wnacg.com/photos-index-aid-{aid}.html",
            };
            byAid[aid] = item;
            results.Add(item);
        }

        // Chrome / Edge / Firefox exported bookmarks use <A HREF="...">Title</A>.
        foreach (
            Match match in Regex.Matches(
                text,
                "<a\\s+[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
                RegexOptions.IgnoreCase | RegexOptions.Singleline
            )
        )
        {
            Add(match.Groups[1].Value, match.Groups[2].Value);
        }

        // Plain URL lists (and any URLs the anchor regex missed).
        foreach (
            Match match in Regex.Matches(
                text,
                "https?://[^\\s\"'<>]+",
                RegexOptions.IgnoreCase
            )
        )
        {
            Add(match.Value, null);
        }

        // Bare album ids, one per line.
        foreach (var line in text.Split('\n'))
        {
            var trimmed = line.Trim();
            if (Regex.IsMatch(trimmed, "^\\d{3,}$"))
            {
                Add($"https://www.wnacg.com/photos-index-aid-{trimmed}.html", null);
            }
        }

        return results;
    }
}
