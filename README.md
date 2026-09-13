# WRD WebVPN Converter App

Universal SwiftUI client for iOS and macOS, based on the sibling
`WRD-WengineVPN-Proxy-Converter` Python project.

## Implemented

- Responsive iOS/macOS GUI for gateway, Cookie, AES key/IV, domain allowlist,
  direct gateway paths, and local proxy port.
- Configuration validation and persistence. The authentication Cookie is stored
  in Keychain and is passed to the extension only when starting a session; it is
  not persisted in `NETunnelProviderProtocol.providerConfiguration`.
- Pure Swift AES-CFB128 implementation compatible with PyCryptodome's
  `AES.MODE_CFB, segment_size=128`.
- Wengine URL encryption, decryption, URL generation, and round-trip preview.
- `NETunnelProviderManager` installation/status control and an embedded,
  universal Packet Tunnel extension target with the required entitlements.

## Important limitation

Wengine WebVPN is an HTTP application gateway, not an IP tunnel. The original
Python program gets HTTPS request URLs by terminating TLS with `mitmproxy`. A
Packet Tunnel extension receives IP packets and cannot see HTTPS URLs or rewrite
them by itself.

The extension therefore deliberately refuses to report a successful connection
until a TLS-capable proxy engine is integrated. This avoids a misleading VPN
status and prevents device traffic from being black-holed. A production tunnel
must provide all of the following:

1. A maintained packet-to-stream or local HTTP proxy engine suitable for an
   Apple Network Extension.
2. TLS interception, certificate generation, and a user-managed trusted CA for
   allowlisted HTTPS hosts.
3. The request/response rewrite behavior from `webvpn_proxy.py`, including
   redirect restoration and direct-path bypass.
4. Certificate pinning detection/bypass behavior and clear privacy disclosure.

## Building

Open `WRDWebVPN-Convert.xcodeproj`, select a development team that has the
Network Extensions capability, and build the `WRDWebVPN-Convert` scheme for iOS
or macOS. The app and `PacketTunnel` target use these bundle identifiers:

- `zone.phg.WRDWebVPN-Convert`
- `zone.phg.WRDWebVPN-Convert.PacketTunnel`

Network Extension profiles must include the `packet-tunnel-provider`
entitlement. Unsigned compilation can be checked with:

```sh
xcodebuild -project WRDWebVPN-Convert.xcodeproj \
  -scheme WRDWebVPN-Convert \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```
