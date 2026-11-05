using System.Collections.Concurrent;
using System.Net;
using System.Text.RegularExpressions;

namespace WnacgDownloader.Core;

public static class HtmlParser
{
    private static readonly ConcurrentDictionary<string, Regex> RegexCache = new();

    public static Regex Rx(string pattern) =>
        RegexCache.GetOrAdd(
            pattern,
            p => new Regex(
                p,
                RegexOptions.IgnoreCase
                    | RegexOptions.Singleline
                    | RegexOptions.CultureInvariant,
                TimeSpan.FromSeconds(8)
            )
        );

    public static string? First(string pattern, string text)
    {
        var match = Rx(pattern).Match(text);
        return match.Success
            ? (match.Groups.Count > 1 ? match.Groups[1].Value : match.Value)
            : null;
    }

    public static List<string> All(string pattern, string text)
    {
        var values = new List<string>();
        foreach (Match match in Rx(pattern).Matches(text))
        {
            values.Add(match.Groups.Count > 1 ? match.Groups[1].Value : match.Value);
        }

        return values;
    }

    public static string StripTags(string html) =>
        Rx("<[^>]+>").Replace(html, " ");

    public static string DecodeEntities(string value) => WebUtility.HtmlDecode(value);

    public static string Clean(string html)
    {
        var text = DecodeEntities(StripTags(html));
        text = Rx("\\s+").Replace(text, " ");
        return text.Trim();
    }

    public static string? NormalizeUrl(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var url = DecodeEntities(raw).Trim().Trim('"', '\'');
        if (url.StartsWith("////", StringComparison.Ordinal))
        {
            url = "https:" + url[2..];
        }
        else if (url.StartsWith("//", StringComparison.Ordinal))
        {
            url = "https:" + url;
        }
        else if (url.StartsWith('/'))
        {
            url = "https://www.wnacg.com" + url;
        }
        else if (!url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                 !url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            url = "https://www.wnacg.com/" + url.TrimStart('/');
        }

        if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            return uri.AbsoluteUri;
        }

        return url;
    }

    public static string SafeFilename(string name, int limit = 140)
    {
        var invalid = Rx("[<>:\"/\\\\|?*\\x00-\\x1F]");
        var value = invalid.Replace(name ?? "", "_");
        value = Rx("\\s+").Replace(value, " ").Trim().Trim('.');
        if (string.IsNullOrWhiteSpace(value))
        {
            value = "untitled";
        }

        var reserved = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "CON", "PRN", "AUX", "NUL",
            "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
            "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        };
        if (reserved.Contains(value.Split('.')[0]))
        {
            value = "_" + value;
        }

        if (value.Length > limit)
        {
            value = value[..limit].Trim().Trim('.');
        }

        return value;
    }

    public static string GuessImageExtension(string url)
    {
        try
        {
            var ext = Path.GetExtension(new Uri(url).AbsolutePath).ToLowerInvariant();
            if (ext is ".jpg" or ".jpeg" or ".png" or ".webp" or ".gif" or ".bmp")
            {
                return ext;
            }
        }
        catch
        {
            // Fall through to the default.
        }

        return ".jpg";
    }
}
