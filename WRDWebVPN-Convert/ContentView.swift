//
//  ContentView.swift
//  WRDWebVPN-Convert
//
//  Created by Phineas Guo on 2026/9/13.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationTitle("WRD WebVPN")
        } detail: {
            NavigationStack {
                switch selection ?? .dashboard {
                case .dashboard: DashboardView(model: model)
                case .configuration: ConfigurationView(model: model)
                case .converter: ConverterView(model: model)
                case .about: AboutView()
                }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { model.notice != nil },
            set: { if !$0 { model.notice = nil } }
        )) {
            Button("好") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, configuration, converter, about
    var id: Self { self }
    var title: String {
        switch self {
        case .dashboard: "连接"
        case .configuration: "配置"
        case .converter: "URL 转换"
        case .about: "说明"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "network"
        case .configuration: "slider.horizontal.3"
        case .converter: "arrow.left.arrow.right"
        case .about: "info.circle"
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var vpn: VPNController

    init(model: AppModel) {
        self.model = model
        vpn = model.vpn
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                ZStack {
                    Circle().fill(.tint.opacity(0.12)).frame(width: 170, height: 170)
                    Image(systemName: vpn.state == .connected ? "lock.shield.fill" : "lock.shield")
                        .font(.system(size: 68)).foregroundStyle(.tint)
                }
                VStack(spacing: 6) {
                    Text(vpn.state.title).font(.title.bold())
                    Text(model.configuration.normalizedGatewayURL?.host ?? "尚未配置网关")
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await model.connectOrDisconnect() }
                } label: {
                    Text(vpn.state == .connected ? "断开连接" : "连接 VPN")
                        .frame(maxWidth: 280).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled([.loading, .connecting, .disconnecting].contains(vpn.state))

                Label("HTTPS 隧道内核尚未集成，当前连接会安全地拒绝启动", systemImage: "hammer.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let error = vpn.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).padding()
                }
                GroupBox("当前路由") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("代理域名", value: "\(model.configuration.proxyDomains.count)")
                        LabeledContent("直通路径", value: "\(model.configuration.directPathPrefixes.count)")
                        LabeledContent("本地端口", value: "\(model.configuration.listenPort)")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: 520)
            }.padding()
        }
        .navigationTitle("连接")
    }
}

private struct ConfigurationView: View {
    @ObservedObject var model: AppModel
    @State private var newDomain = ""
    @State private var newPath = ""

    var body: some View {
        Form {
            Section("WebVPN 网关") {
                TextField("https://vpn.example.edu", text: $model.configuration.gatewayURL)
                    .textContentType(.URL).platformTextInputTraits()
                TextField("Cookie 名称", text: $model.configuration.cookieName).platformTextInputTraits()
                SecureField("Cookie 值", text: $model.cookie).textContentType(.password)
            }
            Section("Wengine 加密") {
                SecureField("AES 密钥", text: $model.configuration.encryptionKey)
                SecureField("初始化向量", text: $model.configuration.initializationVector)
                Text("默认值均为 Wengine 的 16 字节密钥。仅在学校部署不同配置时修改。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            EditableStringList(
                title: "代理域名白名单", placeholder: "example.edu",
                values: $model.configuration.proxyDomains, newValue: $newDomain,
                normalize: WebVPNConfiguration.normalizedDomain
            )
            EditableStringList(
                title: "网关直通路径", placeholder: "/wengine-vpn/",
                values: $model.configuration.directPathPrefixes, newValue: $newPath,
                normalize: { value in
                    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return nil }
                    return value.hasPrefix("/") ? value : "/" + value
                }
            )
            Section("本地代理") {
                TextField("端口", value: $model.configuration.listenPort, format: .number)
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
            }
            if !model.configuration.validationIssues.isEmpty {
                Section("需要修正") {
                    ForEach(model.configuration.validationIssues, id: \.self) {
                        Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("配置")
        .toolbar { Button("保存") { model.save() } }
    }
}

private struct EditableStringList: View {
    let title: String
    let placeholder: String
    @Binding var values: [String]
    @Binding var newValue: String
    let normalize: (String) -> String?

    var body: some View {
        Section(title) {
            ForEach(values, id: \.self) { value in
                HStack {
                    Text(value)
                    Spacer()
                    Button(role: .destructive) { values.removeAll { $0 == value } } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("删除 \(value)")
                }
            }
            HStack {
                TextField(placeholder, text: $newValue).platformTextInputTraits()
                Button("添加") {
                    guard let value = normalize(newValue), !values.contains(value) else { return }
                    values.append(value)
                    newValue = ""
                }.disabled(normalize(newValue) == nil)
            }
        }
    }
}

private struct ConverterView: View {
    @ObservedObject var model: AppModel
    @State private var output = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("输入") {
                TextField("https://github.com/", text: $model.sampleURL, axis: .vertical)
                    .lineLimit(2...5).platformTextInputTraits()
                HStack {
                    Button("转换为 WebVPN URL") { convert(encrypting: true) }.buttonStyle(.borderedProminent)
                    Button("还原原始 URL") { convert(encrypting: false) }.buttonStyle(.bordered)
                }
            }
            Section("结果") {
                if let error { Label(error, systemImage: "xmark.circle.fill").foregroundStyle(.red) }
                else if output.isEmpty { Text("结果会显示在这里").foregroundStyle(.secondary) }
                else {
                    Text(output).textSelection(.enabled)
                    Button("复制") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                        #else
                        UIPasteboard.general.string = output
                        #endif
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("URL 转换")
    }

    private func convert(encrypting: Bool) {
        do {
            guard let url = URL(string: model.sampleURL) else { throw WengineConversionError.invalidURL }
            let converter = WengineURLConverter(configuration: model.configuration)
            output = try (encrypting ? converter.webVPNURL(for: url) : converter.originalURL(from: url)).absoluteString
            error = nil
        } catch {
            output = ""
            self.error = error.localizedDescription
        }
    }
}

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Wengine WebVPN Converter", systemImage: "lock.shield.fill").font(.title.bold())
                Text("将指定域名的 HTTP 请求转换为 Wengine WebVPN 加密 URL。配置与 iOS、macOS 共用；认证 Cookie 存储在系统钥匙串中。")
                GroupBox("HTTPS 说明") {
                    Text("原 Python 项目依赖 mitmproxy 解密 HTTPS。Apple Network Extension 本身不会获得 TLS 明文；若要让 Safari 和其他 App 的 HTTPS 请求透明改写，发布版本仍需集成经过安全审计的 TLS 代理内核并由用户安装、信任其 CA 证书。")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("安全") {
                    Text("只应连接你拥有或已获授权使用的 WebVPN 账户。不要向他人分享 Cookie，也不要在不可信设备上安装代理 CA。")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: 680, alignment: .leading).padding(24)
        }.navigationTitle("说明")
    }
}

private extension View {
    @ViewBuilder
    func platformTextInputTraits() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self
        #endif
    }
}

#Preview {
    ContentView(model: AppModel())
}
