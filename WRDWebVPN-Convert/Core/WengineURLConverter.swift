import Foundation

enum WengineConversionError: LocalizedError {
    case invalidConfiguration(String)
    case invalidURL
    case invalidEncodedPath
    case invalidPlaintext

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .invalidURL: "请输入包含协议与域名的完整 URL"
        case .invalidEncodedPath: "未找到有效的 Wengine 加密路径"
        case .invalidPlaintext: "解密结果不是有效的 UTF-8 域名"
        }
    }
}

struct WengineURLConverter: Sendable {
    let configuration: WebVPNConfiguration

    func encryptAuthority(_ authority: String) throws -> String {
        try validateConfiguration()
        let iv = Data(configuration.initializationVector.utf8)
        let ciphertext = try AESCFB.encrypt(
            Data(authority.utf8), key: Data(configuration.encryptionKey.utf8), iv: iv
        )
        return iv.hexString + ciphertext.hexString
    }

    func decryptAuthority(_ encoded: String) throws -> String {
        try validateConfiguration()
        guard encoded.count >= 32 else { throw WengineConversionError.invalidEncodedPath }
        let plaintext = try AESCFB.decrypt(
            Data(hexString: String(encoded.dropFirst(32))),
            key: Data(configuration.encryptionKey.utf8),
            iv: Data(configuration.initializationVector.utf8)
        )
        guard let authority = String(data: plaintext, encoding: .utf8),
              !authority.isEmpty,
              !authority.contains(where: { "/?#\r\n".contains($0) }) else {
            throw WengineConversionError.invalidPlaintext
        }
        return authority
    }

    func webVPNURL(for originalURL: URL) throws -> URL {
        try validateConfiguration()
        guard let scheme = originalURL.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let authority = originalURL.authority, let gateway = configuration.normalizedGatewayURL else {
            throw WengineConversionError.invalidURL
        }
        let encrypted = try encryptAuthority(authority)
        var components = URLComponents(url: gateway, resolvingAgainstBaseURL: false)
        let originalComponents = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        let gatewayPath = components?.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let encodedOriginalPath = originalComponents?.percentEncodedPath ?? ""
        let originalPath = encodedOriginalPath.isEmpty ? "/" : encodedOriginalPath
        components?.percentEncodedPath = "/" + [gatewayPath, scheme, encrypted].filter { !$0.isEmpty }.joined(separator: "/") + originalPath
        components?.percentEncodedQuery = originalComponents?.percentEncodedQuery
        components?.fragment = nil
        guard let result = components?.url else { throw WengineConversionError.invalidURL }
        return result
    }

    func originalURL(from webVPNURL: URL) throws -> URL {
        try validateConfiguration()
        guard let gateway = configuration.normalizedGatewayURL,
              webVPNURL.host?.lowercased() == gateway.host?.lowercased() else {
            throw WengineConversionError.invalidEncodedPath
        }
        let gatewayParts = gateway.path.split(separator: "/").map(String.init)
        let parts = webVPNURL.path.split(separator: "/").map(String.init)
        guard parts.count >= gatewayParts.count + 2,
              Array(parts.prefix(gatewayParts.count)) == gatewayParts else {
            throw WengineConversionError.invalidEncodedPath
        }
        let scheme = parts[gatewayParts.count]
        guard ["http", "https"].contains(scheme) else { throw WengineConversionError.invalidEncodedPath }
        let authority = try decryptAuthority(parts[gatewayParts.count + 1])
        let authorityParts = authority.split(separator: ":", maxSplits: 1)
        var components = URLComponents()
        components.scheme = scheme
        components.host = authorityParts.first.map(String.init)
        if authorityParts.count == 2 { components.port = Int(authorityParts[1]) }
        components.percentEncodedPath = "/" + parts.dropFirst(gatewayParts.count + 2).joined(separator: "/")
        components.percentEncodedQuery = URLComponents(url: webVPNURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        components.fragment = webVPNURL.fragment
        guard let result = components.url else { throw WengineConversionError.invalidURL }
        return result
    }

    private func validateConfiguration() throws {
        if let issue = configuration.validationIssues.first {
            throw WengineConversionError.invalidConfiguration(issue)
        }
    }
}

private extension URL {
    var authority: String? {
        guard let host else { return nil }
        return port.map { "\(host):\($0)" } ?? host
    }
}
