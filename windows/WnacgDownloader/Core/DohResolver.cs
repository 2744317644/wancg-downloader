using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Text.Json;

namespace WnacgDownloader.Core;

/// <summary>
/// Resolves hostnames through DNS-over-HTTPS and validates the returned IPs
/// with a real TLS handshake (SNI = original host), then connects directly.
/// This mirrors the iOS app's "DoH direct" mode.
/// </summary>
public sealed class DohResolver : IDisposable
{
    private const string DefaultEndpoint =
        "https://cloudflare-dns.com/dns-query?name={host}&type=A";

    private static readonly string[] FallbackEndpoints =
    {
        "https://dns.alidns.com/resolve?name={host}&type=1",
        "https://doh.pub/dns-query?name={host}&type=A",
    };

    private readonly string _endpointTemplate;
    private readonly HttpClient _http;
    private readonly Dictionary<string, CacheEntry> _cache = new();
    private readonly object _lock = new();

    private sealed record CacheEntry(DateTime Expires, List<IPAddress> Ips);

    public DohResolver(string? endpointTemplate)
    {
        _endpointTemplate = string.IsNullOrWhiteSpace(endpointTemplate)
            ? DefaultEndpoint
            : endpointTemplate.Trim();

        _http = new HttpClient(
            new SocketsHttpHandler
            {
                UseProxy = false,
                AllowAutoRedirect = true,
                ConnectTimeout = TimeSpan.FromSeconds(10),
            }
        )
        {
            Timeout = TimeSpan.FromSeconds(12),
        };
        _http.DefaultRequestHeaders.Accept.ParseAdd("application/dns-json");
        _http.DefaultRequestHeaders.UserAgent.ParseAdd(WnacgClient.UserAgent);
    }

    public async Task<IReadOnlyList<IPAddress>> ResolveAsync(
        string host,
        CancellationToken ct
    )
    {
        host = host.Trim().Trim('[', ']');
        if (IPAddress.TryParse(host, out var literal))
        {
            return new[] { literal };
        }

        lock (_lock)
        {
            if (_cache.TryGetValue(host, out var cached) && cached.Expires > DateTime.UtcNow)
            {
                return cached.Ips;
            }
        }

        var candidates = new List<IPAddress>();
        foreach (var template in new[] { _endpointTemplate }.Concat(FallbackEndpoints))
        {
            try
            {
                candidates.AddRange(await QueryAsync(template, host, ct));
            }
            catch
            {
                // Try the next endpoint.
            }

            if (candidates.Count > 0)
            {
                break;
            }
        }

        if (candidates.Count == 0)
        {
            try
            {
                candidates.AddRange(await Dns.GetHostAddressesAsync(host, ct));
            }
            catch
            {
                // Handled by the empty-candidates error below.
            }
        }

        var distinct = candidates.Distinct().ToList();
        var valid = await ValidateAsync(host, distinct, ct);
        if (valid.Count == 0)
        {
            // Do not hard-fail on validation errors: some networks block the
            // extra TLS probe but still let the real request through.
            valid = distinct;
        }

        if (valid.Count == 0)
        {
            throw new IOException($"DoH 解析失败：{host}");
        }

        lock (_lock)
        {
            _cache[host] = new CacheEntry(DateTime.UtcNow.AddMinutes(10), valid);
        }

        return valid;
    }

    private async Task<List<IPAddress>> QueryAsync(
        string template,
        string host,
        CancellationToken ct
    )
    {
        var escaped = Uri.EscapeDataString(host);
        var url = template.Contains("{host}", StringComparison.Ordinal)
            ? template.Replace("{host}", escaped, StringComparison.Ordinal)
            : template + (template.Contains('?') ? "&" : "?") + "name=" + escaped + "&type=A";

        using var response = await _http.GetAsync(url, ct);
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("Answer", out var answers) ||
            answers.ValueKind != JsonValueKind.Array)
        {
            return new List<IPAddress>();
        }

        var ips = new List<IPAddress>();
        var cnames = new List<string>();
        foreach (var answer in answers.EnumerateArray())
        {
            if (!answer.TryGetProperty("type", out var type) ||
                !answer.TryGetProperty("data", out var data) ||
                data.ValueKind != JsonValueKind.String)
            {
                continue;
            }

            var typeValue = type.ValueKind == JsonValueKind.Number
                ? type.GetInt32().ToString()
                : type.GetString();
            var value = data.GetString()?.Trim();
            if (string.IsNullOrEmpty(value))
            {
                continue;
            }

            if (typeValue == "1" && IPAddress.TryParse(value, out var ip))
            {
                if (!ips.Contains(ip)) ips.Add(ip);
            }
            else if (typeValue == "5")
            {
                cnames.Add(value.TrimEnd('.'));
            }
        }

        if (ips.Count == 0 && cnames.Count > 0)
        {
            foreach (var cname in cnames)
            {
                try
                {
                    ips.AddRange(await QueryAsync(template, cname, ct));
                }
                catch
                {
                    // Try the next CNAME.
                }
            }
        }

        return ips;
    }

    private static async Task<List<IPAddress>> ValidateAsync(
        string host,
        List<IPAddress> ips,
        CancellationToken ct
    )
    {
        var valid = new List<IPAddress>();
        foreach (var ip in ips.Take(4))
        {
            try
            {
                using var tcp = new TcpClient();
                await tcp.ConnectAsync(ip, 443, ct);
                await using var ssl = new SslStream(tcp.GetStream());
                await ssl.AuthenticateAsClientAsync(
                    new SslClientAuthenticationOptions { TargetHost = host },
                    ct
                );
                valid.Add(ip);
            }
            catch
            {
                // This IP did not present a valid certificate for the host.
            }

            if (valid.Count >= 2)
            {
                break;
            }
        }

        return valid;
    }

    public void Dispose() => _http.Dispose();
}
