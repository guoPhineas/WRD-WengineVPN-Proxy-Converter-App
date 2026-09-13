import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration: WebVPNConfiguration
    @Published var cookie: String
    @Published var sampleURL: String
    @Published var notice: String?
    let vpn = VPNController()

    private static let settingsKey = "persisted-settings-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let settings = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            configuration = settings.configuration
            sampleURL = settings.sampleURL
        } else {
            configuration = WebVPNConfiguration()
            sampleURL = "https://github.com/"
        }
        cookie = KeychainStore.loadCookie()
    }

    func save() {
        do {
            let value = PersistedSettings(configuration: configuration, sampleURL: sampleURL)
            UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: Self.settingsKey)
            try KeychainStore.saveCookie(cookie)
            notice = "配置已保存"
        } catch {
            notice = error.localizedDescription
        }
    }

    func connectOrDisconnect() async {
        save()
        guard configuration.validationIssues.isEmpty else {
            notice = configuration.validationIssues.joined(separator: "\n")
            return
        }
        guard !cookie.isEmpty else {
            notice = "请先填写认证 Cookie"
            return
        }
        do {
            try await vpn.toggle(configuration: configuration, cookie: cookie)
        } catch {
            notice = error.localizedDescription
        }
    }
}
