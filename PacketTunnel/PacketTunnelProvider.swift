import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol,
              let configuration = tunnelProtocol.providerConfiguration,
              configuration["gatewayURL"] as? String != nil,
              options?["cookieValue"] as? String != nil else {
            completionHandler(PacketTunnelError.invalidConfiguration)
            return
        }

        // Wengine is an application-layer WebVPN, not an IP tunnel. The Python
        // implementation relies on mitmproxy to terminate TLS before rewriting
        // URLs. Do not claim a connected tunnel until that audited TLS engine is
        // embedded here; doing so would divert and black-hole device traffic.
        completionHandler(PacketTunnelError.tlsProxyEngineUnavailable)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

private enum PacketTunnelError: Int, LocalizedError {
    case invalidConfiguration = 1
    case tlsProxyEngineUnavailable = 2

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Wengine VPN 配置不完整"
        case .tlsProxyEngineUnavailable: "尚未集成 HTTPS 代理内核；为避免中断网络，隧道未启动"
        }
    }
}
