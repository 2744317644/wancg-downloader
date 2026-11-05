using System.Collections.ObjectModel;

namespace WnacgDownloader.Core;

public enum NetworkMode
{
    SystemProxy,
    Doh,
}

public sealed class AppSettings
{
    public string DownloadDirectory { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        "Downloads",
        "wnacg"
    );

    public NetworkMode NetworkMode { get; set; } = NetworkMode.SystemProxy;

    /// <summary>Use 127.0.0.1:&lt;ProxyPort&gt; instead of the Windows system proxy.</summary>
    public bool UseCustomProxyPort { get; set; }

    public int ProxyPort { get; set; } = 7890;

    /// <summary>DoH JSON endpoint; {host} is replaced with the DNS name.</summary>
    public string DohEndpoint { get; set; } =
        "https://cloudflare-dns.com/dns-query?name={host}&type=A";

    public int ImageConcurrency { get; set; } = 4;

    public bool CreateZip { get; set; } = true;
}

public sealed class AlbumPreview
{
    public string Aid { get; set; } = "";
    public string Title { get; set; } = "未命名作品";
    public string? CoverUrl { get; set; }
    public int? Pages { get; set; }
    public string Category { get; set; } = "";
    public List<string> Tags { get; set; } = new();
    public string Uploader { get; set; } = "";
    public string Uploaded { get; set; } = "";
    public string PageUrl { get; set; } = "";

    public string MetaLine
    {
        get
        {
            var parts = new List<string>();
            if (!string.IsNullOrWhiteSpace(Category)) parts.Add(Category);
            if (Pages is int pages) parts.Add($"{pages}P");
            if (!string.IsNullOrWhiteSpace(Uploader)) parts.Add(Uploader);
            if (!string.IsNullOrWhiteSpace(Uploaded)) parts.Add(Uploaded);
            return string.Join(" · ", parts);
        }
    }
}

public sealed class BookmarkItem
{
    public string Aid { get; set; } = "";
    public string Title { get; set; } = "";
    public string Url { get; set; } = "";

    public string Display =>
        string.IsNullOrWhiteSpace(Title) ? $"aid {Aid} — {Url}" : $"{Title} — {Url}";
}

public sealed record DownloadProgress(
    int Done,
    int Total,
    long Bytes,
    string Status
)
{
    public double Fraction => Total > 0 ? Math.Clamp((double)Done / Total, 0, 1) : 0;
}
