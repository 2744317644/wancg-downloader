using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.RegularExpressions;

namespace WnacgDownloader.Core;

public sealed class WnacgException : Exception
{
    public WnacgException(string message) : base(message) { }
}

public sealed class WnacgClient : IDisposable
{
    public const string UserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

    private const string Host = "https://www.wnacg.com";

    private readonly HttpClient _http;
    private readonly DohResolver? _doh;

    public WnacgClient(AppSettings settings)
    {
        var handler = new SocketsHttpHandler
        {
            AllowAutoRedirect = true,
            AutomaticDecompression = DecompressionMethods.All,
            ConnectTimeout = TimeSpan.FromSeconds(20),
            PooledConnectionLifetime = TimeSpan.FromMinutes(4),
            MaxConnectionsPerServer = 8,
        };

        if (settings.NetworkMode == NetworkMode.Doh)
        {
            handler.UseProxy = false;
            _doh = new DohResolver(settings.DohEndpoint);
            handler.ConnectCallback = async (context, ct) =>
            {
                var ips = await _doh.ResolveAsync(context.DnsEndPoint.Host, ct);
                Exception? lastError = null;
                foreach (var ip in ips)
                {
                    var socket = new System.Net.Sockets.Socket(
                        ip.AddressFamily,
                        System.Net.Sockets.SocketType.Stream,
                        System.Net.Sockets.ProtocolType.Tcp
                    );
                    try
                    {
                        await socket.ConnectAsync(
                            new IPEndPoint(ip, context.DnsEndPoint.Port),
                            ct
                        );
                        return new System.Net.Sockets.NetworkStream(socket, ownsSocket: true);
                    }
                    catch (Exception ex)
                    {
                        lastError = ex;
                        socket.Dispose();
                    }
                }

                throw lastError ?? new IOException(
                    $"无法连接 {context.DnsEndPoint.Host}"
                );
            };
        }
        else
        {
            handler.UseProxy = true;
            handler.Proxy = settings.UseCustomProxyPort
                ? new WebProxy("127.0.0.1", settings.ProxyPort)
                : HttpClient.DefaultProxy;
        }

        _http = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(120),
        };
        _http.DefaultRequestHeaders.UserAgent.ParseAdd(UserAgent);
        _http.DefaultRequestHeaders.AcceptLanguage.ParseAdd("zh-CN,zh;q=0.9,en;q=0.7");
        _http.DefaultRequestHeaders.Accept.ParseAdd(
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8"
        );
    }

    public async Task<AlbumPreview> GetPreviewAsync(
        string rawInput,
        CancellationToken ct = default
    )
    {
        var (aid, sid) = await ResolveTargetAsync(rawInput, ct);
        var galleryUrl = BuildGalleryUrl(aid, sid);
        var html = await GetStringAsync(galleryUrl, Host, ct);

        var title = HtmlParser.First(
                "id=\"comicName\"[^>]*>(.*?)</div>",
                html
            )
            ?? HtmlParser.First(
                "<div id=\"bodywrap\" class=\"userwrap\">\\s*<h2>(.*?)</h2>",
                html
            )
            ?? HtmlParser.First("<title[^>]*>(.*?)</title>", html);

        var displayTitle = HtmlParser.Clean(title ?? "").Trim();
        displayTitle = Regex.Replace(
            displayTitle,
            "\\s*[-–—|]\\s*紳士漫畫.*$",
            ""
        ).Trim();
        if (string.IsNullOrWhiteSpace(displayTitle))
        {
            displayTitle = "未命名作品";
        }

        var thumbBlock = HtmlParser.First(
            "<div class=\"asTBcell uwthumb\">(.*?)</div>",
            html
        );
        var coverRaw = thumbBlock == null
            ? null
            : HtmlParser.First("<img[^>]+src=\"([^\"]+)\"", thumbBlock);
        coverRaw ??= HtmlParser.First(
            "id=\"Cover\"[^>]*>\\s*<img[^>]+src=\"([^\"]+)\"",
            html
        );

        var category = "";
        int? pages = null;
        foreach (var label in HtmlParser.All("<label[^>]*>(.*?)</label>", html))
        {
            var text = HtmlParser.Clean(label);
            if (text.StartsWith("分類：", StringComparison.Ordinal))
            {
                category = text["分類：".Length..];
            }
            else if (text.StartsWith("頁數：", StringComparison.Ordinal))
            {
                var raw = text["頁數：".Length..]
                    .Replace("P", "", StringComparison.OrdinalIgnoreCase)
                    .Trim();
                if (int.TryParse(raw, out var parsed)) pages = parsed;
            }
        }

        if (string.IsNullOrWhiteSpace(category))
        {
            category =
                HtmlParser.First(
                    "class=\"pd\"[^>]*href=\"/albums-index-cate-\\d+\\.html\"[^>]*>(.*?)</a>",
                    html
                )?.Pipe(HtmlParser.Clean)
                ?? "";
        }

        if (pages is null)
        {
            var dateText = HtmlParser.First(
                "<span class=\"date\">(.*?)</span>",
                html
            );
            if (dateText != null)
            {
                var match = Regex.Match(HtmlParser.Clean(dateText), "(\\d+)\\s*P");
                if (match.Success) pages = int.Parse(match.Groups[1].Value);
            }
        }

        pages ??= HtmlParser
            .First("(\\d+)\\s*P\\s*·", html)
            ?.Pipe(s => int.TryParse(s, out var n) ? n : (int?)null);

        var tags = HtmlParser
            .All("<a class=\"tagshow\"[^>]*>(.*?)</a>", html)
            .Select(HtmlParser.Clean)
            .Concat(
                HtmlParser
                    .All("<a class=\"dv-tag\"[^>]*>(.*?)</a>", html)
                    .Select(HtmlParser.Clean)
            )
            .Where(t => !string.IsNullOrWhiteSpace(t))
            .Distinct()
            .ToList();

        var uploader = HtmlParser
            .First(
                "<a href=\"/albums-user-uid-\\d+\\.html\">.*?<p>(.*?)</p>",
                html
            )
            ?.Pipe(HtmlParser.Clean)
            ?? HtmlParser
                .First("class=\"pd introName\"[^>]*>(.*?)</a>", html)
                ?.Pipe(HtmlParser.Clean)
            ?? "";

        var uploaded =
            HtmlParser.First("上傳於\\s*(\\d{4}-\\d{2}-\\d{2})", html) ?? "";

        return new AlbumPreview
        {
            Aid = aid,
            Title = displayTitle,
            CoverUrl = HtmlParser.NormalizeUrl(coverRaw),
            Pages = pages,
            Category = category,
            Tags = tags,
            Uploader = uploader,
            Uploaded = uploaded,
            PageUrl = galleryUrl,
        };
    }

    public async Task<List<string>> GetPageUrlsAsync(
        string aid,
        CancellationToken ct = default
    )
    {
        var itemUrl = $"{Host}/photos-item-aid-{aid}.html";
        var galleryUrl = BuildGalleryUrl(aid, null);
        var html = await GetStringAsync(itemUrl, galleryUrl, ct);
        var arrayText = HtmlParser.First("\"page_url\"\\s*:\\s*\\[(.*?)\\]", html);
        if (arrayText == null)
        {
            throw new WnacgException("阅读页没有找到图片地址（可能需要登录或作品已下架）。");
        }

        var urls = HtmlParser
            .All("\"(https?://[^\"]+)\"", arrayText)
            .Select(u => HtmlParser.NormalizeUrl(u.Replace("\\/", "/")))
            .Where(u => !string.IsNullOrWhiteSpace(u))
            .Select(u => u!.Replace("http://", "https://"))
            .Distinct()
            .ToList();

        if (urls.Count == 0)
        {
            throw new WnacgException("阅读页没有图片。");
        }

        return urls;
    }

    public async Task<byte[]> GetBytesAsync(
        string url,
        string? referer,
        CancellationToken ct = default
    )
    {
        var (bytes, _) = await GetBytesCoreAsync(url, referer, ct);
        return bytes;
    }

    public async Task<string> GetStringAsync(
        string url,
        string? referer,
        CancellationToken ct = default
    )
    {
        var (bytes, charset) = await GetBytesCoreAsync(url, referer, ct);
        if (IsCloudflareChallenge(bytes))
        {
            throw new WnacgException(
                "站点触发了 Cloudflare 人机验证。请换一个网络/代理，或稍后再试。"
            );
        }

        if (!string.IsNullOrWhiteSpace(charset))
        {
            try
            {
                return Encoding.GetEncoding(charset).GetString(bytes);
            }
            catch
            {
                // Fall back to UTF-8.
            }
        }

        return Encoding.UTF8.GetString(bytes);
    }

    private async Task<(byte[] Bytes, string? Charset)> GetBytesCoreAsync(
        string url,
        string? referer,
        CancellationToken ct
    )
    {
        Exception? lastError = null;
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                if (!string.IsNullOrWhiteSpace(referer) &&
                    Uri.TryCreate(referer, UriKind.Absolute, out var refererUri))
                {
                    request.Headers.Referrer = refererUri;
                }

                using var response = await _http.SendAsync(
                    request,
                    HttpCompletionOption.ResponseHeadersRead,
                    ct
                );

                if ((int)response.StatusCode == 429 && attempt < 3)
                {
                    await Task.Delay(TimeSpan.FromSeconds(attempt * 2), ct);
                    continue;
                }

                if (!response.IsSuccessStatusCode)
                {
                    throw new WnacgException(
                        $"访问失败：HTTP {(int)response.StatusCode}（{url}）"
                    );
                }

                var bytes = await response.Content.ReadAsByteArrayAsync(ct);
                var charset = response.Content.Headers.ContentType?.CharSet;
                if (!string.IsNullOrWhiteSpace(charset))
                {
                    charset = charset.Trim('"', '\'');
                }

                return (bytes, charset);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (WnacgException)
            {
                throw;
            }
            catch (Exception ex) when (attempt < 3)
            {
                lastError = ex;
                await Task.Delay(TimeSpan.FromSeconds(attempt), ct);
            }
        }

        throw new WnacgException(
            $"访问失败：{url}\n{lastError?.Message ?? "未知错误"}"
        );
    }

    private static bool IsCloudflareChallenge(byte[] bytes)
    {
        if (bytes.Length == 0 || bytes.Length > 200_000)
        {
            return false;
        }

        var head = Encoding.UTF8.GetString(
            bytes,
            0,
            Math.Min(bytes.Length, 64 * 1024)
        );
        return head.Contains("Just a moment", StringComparison.OrdinalIgnoreCase)
            || head.Contains("cf-challenge", StringComparison.OrdinalIgnoreCase)
            || head.Contains(
                "Attention Required! | Cloudflare",
                StringComparison.OrdinalIgnoreCase
            );
    }

    private async Task<(string Aid, string? Sid)> ResolveTargetAsync(
        string rawInput,
        CancellationToken ct
    )
    {
        var input = (rawInput ?? "").Trim().Trim('"', '\'');
        if (string.IsNullOrWhiteSpace(input))
        {
            throw new WnacgException("请先粘贴作品链接。");
        }

        var aidMatch = Regex.Match(input, "aid-(\\d+)", RegexOptions.IgnoreCase);
        if (aidMatch.Success)
        {
            var sidMatch = Regex.Match(input, "\\?s=([\\w-]+)");
            return (aidMatch.Groups[1].Value, sidMatch.Success ? sidMatch.Groups[1].Value : null);
        }

        if (Regex.IsMatch(input, "^\\d+$"))
        {
            return (input, null);
        }

        if (!input.StartsWith("http", StringComparison.OrdinalIgnoreCase))
        {
            input = "https://" + input;
        }

        var html = await GetStringAsync(input, Host, ct);
        var fromPage = Regex.Match(html, "/photos-index-aid-(\\d+)\\.html");
        if (!fromPage.Success)
        {
            throw new WnacgException(
                "无法识别这个链接。请使用作品页，例如：\n" +
                "https://www.wnacg.com/photos-index-aid-383877.html"
            );
        }

        var sid = Regex.Match(
            html,
            $"/photos-index-aid-{fromPage.Groups[1].Value}\\.html\\?s=([\\w-]+)"
        );
        return (
            fromPage.Groups[1].Value,
            sid.Success ? sid.Groups[1].Value : null
        );
    }

    private static string BuildGalleryUrl(string aid, string? sid)
    {
        var url = $"{Host}/photos-index-aid-{aid}.html";
        return string.IsNullOrWhiteSpace(sid)
            ? url
            : url + "?s=" + Uri.EscapeDataString(sid);
    }

    public void Dispose()
    {
        _http.Dispose();
        _doh?.Dispose();
    }
}

internal static class PipeExtensions
{
    public static TResult Pipe<T, TResult>(this T value, Func<T, TResult> mapper) =>
        mapper(value);
}
