import Foundation
import NetworkExtension
import Combine

@MainActor
final class VPNController: NSObject, ObservableObject {
    enum State: Equatable {
        case loading, disconnected, connecting, connected, disconnecting, invalid

        var title: String {
            switch self {
            case .loading: "正在读取…"
            case .disconnected: "未连接"
            case .connecting: "正在连接…"
            case .connected: "已连接"
            case .disconnecting: "正在断开…"
            case .invalid: "配置不可用"
            }
        }
    }

    static let providerBundleIdentifier = "zone.phg.WRDWebVPN-Convert.PacketTunnel"
    @Published var state: State = .loading
    @Published var lastError: String?
    private var manager: NETunnelProviderManager?

    override init() {
        super.init()
        Task { await load() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.providerBundleIdentifier }
            observeStatus()
            refreshState()
        } catch {
            state = .invalid
            lastError = error.localizedDescription
        }
    }

    func toggle(configuration: WebVPNConfiguration, cookie: String) async throws {
        if state == .connected || state == .connecting {
            manager?.connection.stopVPNTunnel()
            return
        }
        try await install(configuration: configuration)
        guard let manager,
              let session = manager.connection as? NETunnelProviderSession else {
            throw VPNControllerError.managerUnavailable
        }
        do {
            try session.startTunnel(options: ["cookieValue": cookie as NSString])
            refreshState()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func install(configuration: WebVPNConfiguration) async throws {
        let activeManager = manager ?? NETunnelProviderManager()
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = Self.providerBundleIdentifier
        tunnelProtocol.serverAddress = configuration.normalizedGatewayURL?.host ?? "Wengine WebVPN"
        tunnelProtocol.providerConfiguration = [
            "configurationVersion": 1,
            "gatewayURL": configuration.gatewayURL,
            "cookieName": configuration.cookieName,
            "key": configuration.encryptionKey,
            "iv": configuration.initializationVector,
            "proxyDomains": configuration.proxyDomains,
            "directPathPrefixes": configuration.directPathPrefixes,
            "listenPort": configuration.listenPort
        ]
        activeManager.protocolConfiguration = tunnelProtocol
        activeManager.localizedDescription = "Wengine WebVPN"
        activeManager.isEnabled = true
        try await activeManager.saveToPreferences()
        try await activeManager.loadFromPreferences()
        manager = activeManager
        observeStatus()
    }

    private func observeStatus() {
        NotificationCenter.default.removeObserver(self, name: .NEVPNStatusDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange),
            name: .NEVPNStatusDidChange,
            object: manager?.connection
        )
    }

    @objc private func vpnStatusDidChange() { refreshState() }

    private func refreshState() {
        switch manager?.connection.status ?? .disconnected {
        case .connected: state = .connected
        case .connecting, .reasserting: state = .connecting
        case .disconnecting: state = .disconnecting
        case .disconnected: state = .disconnected
        case .invalid: state = .invalid
        @unknown default: state = .invalid
        }
    }
}

extension VPNController: @unchecked Sendable {}

enum VPNControllerError: LocalizedError {
    case managerUnavailable
    var errorDescription: String? { "无法创建系统 VPN 配置" }
}
