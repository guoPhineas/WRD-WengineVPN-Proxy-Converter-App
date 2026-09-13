import Foundation

struct WebVPNConfiguration: Codable, Equatable, Sendable {
    var gatewayURL = "https://vpn.example.edu"
    var cookieName = "wengine_vpn_ticketvpn_example_edu"
    var encryptionKey = "wrdvpnisthebest!"
    var initializationVector = "wrdvpnisthebest!"
    var proxyDomains = ["github.com"]
    var directPathPrefixes = ["/wengine-vpn/"]
    var listenPort = 9090

    var normalizedGatewayURL: URL? {
        guard let url = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }

    var validationIssues: [String] {
        var issues: [String] = []
        if normalizedGatewayURL == nil { issues.append("网关地址必须是完整的 http:// 或 https:// URL") }
        if cookieName.isEmpty || cookieName.contains(where: { "=; \t\r\n".contains($0) }) {
            issues.append("Cookie 名称无效")
        }
        if ![16, 24, 32].contains(encryptionKey.utf8.count) {
            issues.append("AES 密钥必须是 16、24 或 32 字节")
        }
        if initializationVector.utf8.count != 16 { issues.append("初始化向量必须是 16 字节") }
        if !(1...65535).contains(listenPort) { issues.append("本地代理端口必须在 1…65535 之间") }
        if proxyDomains.contains(where: { Self.normalizedDomain($0) == nil }) {
            issues.append("白名单中包含无效域名")
        }
        return issues
    }

    func isProxyDomain(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return proxyDomains.compactMap(Self.normalizedDomain).contains {
            host == $0 || host.hasSuffix(".\($0)")
        }
    }

    nonisolated static func normalizedDomain(_ value: String) -> String? {
        var domain = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if domain.hasPrefix("*.") { domain.removeFirst(2) }
        domain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !domain.isEmpty, !domain.contains("/"), !domain.contains(" "),
              domain.split(separator: ".").allSatisfy({ !$0.isEmpty }) else { return nil }
        return domain
    }
}

struct PersistedSettings: Codable {
    var configuration: WebVPNConfiguration
    var sampleURL: String
}
