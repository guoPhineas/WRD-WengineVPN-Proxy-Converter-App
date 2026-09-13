import Foundation

enum AESCFBError: LocalizedError {
    case invalidKeyLength
    case invalidIVLength
    case invalidHex

    var errorDescription: String? {
        switch self {
        case .invalidKeyLength: "AES 密钥必须是 16、24 或 32 字节"
        case .invalidIVLength: "初始化向量必须是 16 字节"
        case .invalidHex: "加密内容不是有效的十六进制数据"
        }
    }
}

/// AES-CFB128 compatible with PyCryptodome's `AES.MODE_CFB, segment_size=128`.
enum AESCFB {
    static func encrypt(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
        try transform(plaintext, key: key, iv: iv, decrypting: false)
    }

    static func decrypt(_ ciphertext: Data, key: Data, iv: Data) throws -> Data {
        try transform(ciphertext, key: key, iv: iv, decrypting: true)
    }

    private static func transform(_ input: Data, key: Data, iv: Data, decrypting: Bool) throws -> Data {
        guard [16, 24, 32].contains(key.count) else { throw AESCFBError.invalidKeyLength }
        guard iv.count == 16 else { throw AESCFBError.invalidIVLength }
        let aes = try AES(key: [UInt8](key))
        let bytes = [UInt8](input)
        var feedback = [UInt8](iv)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)

        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let count = min(16, bytes.count - offset)
            let stream = aes.encrypt(block: feedback)
            let source = Array(bytes[offset..<(offset + count)])
            let transformed = zip(source, stream).map { $0 ^ $1 }
            output.append(contentsOf: transformed)
            feedback = decrypting ? source : transformed
        }
        return Data(output)
    }
}

private struct AES {
    private let rounds: Int
    private let roundKeys: [UInt8]

    init(key: [UInt8]) throws {
        guard [16, 24, 32].contains(key.count) else { throw AESCFBError.invalidKeyLength }
        let words = key.count / 4
        rounds = words + 6
        var expanded = key
        expanded.reserveCapacity(16 * (rounds + 1))
        var rcon: UInt8 = 1
        var index = words
        while expanded.count < 16 * (rounds + 1) {
            var temp = Array(expanded[(index - 1) * 4..<index * 4])
            if index % words == 0 {
                temp = [Self.sbox[Int(temp[1])], Self.sbox[Int(temp[2])], Self.sbox[Int(temp[3])], Self.sbox[Int(temp[0])]]
                temp[0] ^= rcon
                rcon = Self.xtime(rcon)
            } else if words > 6 && index % words == 4 {
                temp = temp.map { Self.sbox[Int($0)] }
            }
            let prior = (index - words) * 4
            for byte in 0..<4 { expanded.append(expanded[prior + byte] ^ temp[byte]) }
            index += 1
        }
        roundKeys = expanded
    }

    func encrypt(block: [UInt8]) -> [UInt8] {
        var state = block
        addRoundKey(&state, round: 0)
        for round in 1..<rounds {
            state = state.map { Self.sbox[Int($0)] }
            shiftRows(&state)
            mixColumns(&state)
            addRoundKey(&state, round: round)
        }
        state = state.map { Self.sbox[Int($0)] }
        shiftRows(&state)
        addRoundKey(&state, round: rounds)
        return state
    }

    private func addRoundKey(_ state: inout [UInt8], round: Int) {
        let offset = round * 16
        for index in 0..<16 { state[index] ^= roundKeys[offset + index] }
    }

    private func shiftRows(_ state: inout [UInt8]) {
        let copy = state
        for row in 0..<4 {
            for column in 0..<4 { state[column * 4 + row] = copy[((column + row) % 4) * 4 + row] }
        }
    }

    private func mixColumns(_ state: inout [UInt8]) {
        for column in 0..<4 {
            let i = column * 4
            let a = Array(state[i..<(i + 4)])
            let all = a[0] ^ a[1] ^ a[2] ^ a[3]
            state[i] ^= all ^ Self.xtime(a[0] ^ a[1])
            state[i + 1] ^= all ^ Self.xtime(a[1] ^ a[2])
            state[i + 2] ^= all ^ Self.xtime(a[2] ^ a[3])
            state[i + 3] ^= all ^ Self.xtime(a[3] ^ a[0])
        }
    }

    private static func xtime(_ value: UInt8) -> UInt8 {
        (value << 1) ^ ((value & 0x80) == 0 ? 0 : 0x1b)
    }

    private static let sbox: [UInt8] = [
        0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
        0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
        0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
        0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
        0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
        0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
        0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
        0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
        0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
        0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
        0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
        0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
        0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
        0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
        0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
        0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
    ]
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init(hexString: String) throws {
        guard hexString.count.isMultiple(of: 2), hexString.allSatisfy(\.isHexDigit) else {
            throw AESCFBError.invalidHex
        }
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { throw AESCFBError.invalidHex }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
