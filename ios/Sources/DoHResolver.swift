import Foundation

final class DoHResolver {
    static let shared = DoHResolver()

    // 实测可用的备用 IP；DoH 偶尔会返回污染地址，静态 IP 优先。
    private let staticIPs: [String: [String]] = [
        "www.wnacg.com": ["104.20.44.182", "172.66.175.138"],
        "wnacg.com": ["104.20.44.182", "172.66.175.138"],
        "t4.qy0.ru": ["104.20.44.182", "172.66.175.138"],
        "dl1.wn01.download": ["185.243.218.90", "51.159.194.108"],
        "img4.wnacg.com": ["172.67.74.237", "104.26.12.109"],
        "d1.wcdn.date": ["172.67.158.148", "104.21.33.39"],
    ]

    private struct CacheEntry {
        let expires: Date
        let ips: [String]
    }

    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func resolve(host: String) async throws -> [String] {
        let normalized = host.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if isIPv4(normalized) {
            return [normalized]
        }

        if let cached = cachedIPs(for: normalized) {
            return cached
        }

        if let ips = staticIPs[normalized], !ips.isEmpty {
            store(ips, for: normalized)
            return ips
        }

        let ips = try await query(host: normalized)
        guard !ips.isEmpty else {
            throw WnacgError.message("DoH 无法解析 \(normalized)")
        }
        store(ips, for: normalized)
        return ips
    }

    private func query(host: String) async throws -> [String] {
        var components = URLComponents(string: "https://doh.pub/dns-query")!
        components.queryItems = [
            URLQueryItem(name: "name", value: host),
            URLQueryItem(name: "type", value: "A"),
        ]
        guard let url = components.url else {
            throw WnacgError.message("DoH URL 无效")
        }

        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WnacgError.message("DoH 请求失败")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = object["Answer"] as? [[String: Any]] else {
            return []
        }

        var ips: [String] = []
        var cnames: [String] = []
        for answer in answers {
            guard let type = answer["type"] as? Int,
                  let value = answer["data"] as? String else { continue }
            if type == 1, !ips.contains(value) {
                ips.append(value)
            } else if type == 5 {
                cnames.append(value.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
        }

        if ips.isEmpty {
            for cname in cnames.prefix(2) {
                if let nested = try? await query(host: cname), !nested.isEmpty {
                    return nested
                }
            }
        }
        return ips
    }

    private func isIPv4(_ value: String) -> Bool {
        value.range(
            of: "^\\d{1,3}(\\.\\d{1,3}){3}$", options: .regularExpression
        ) != nil
    }

    private func cachedIPs(for host: String) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[host], entry.expires > Date() else { return nil }
        return entry.ips
    }

    private func store(_ ips: [String], for host: String) {
        lock.lock()
        cache[host] = CacheEntry(expires: Date().addingTimeInterval(600), ips: ips)
        lock.unlock()
    }
}
