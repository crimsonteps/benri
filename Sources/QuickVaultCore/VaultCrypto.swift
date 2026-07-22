import CryptoKit
import Foundation

public enum VaultCryptoError: Error, LocalizedError {
    case invalidFile
    case unsupportedFormat

    public var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "保险库文件无效或已损坏。"
        case .unsupportedFormat:
            return "当前版本无法读取这个保险库文件。"
        }
    }
}

public enum VaultCrypto {
    private static let magic = Data("QVLT".utf8)
    private static let fileVersion: UInt8 = 1

    public static func generateKeyData() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }

    public static func encrypt(_ payload: VaultPayload, keyData: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let plaintext = try encoder.encode(payload)
        let sealedBox = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyData))

        guard let combined = sealedBox.combined else {
            throw VaultCryptoError.invalidFile
        }

        var output = magic
        output.append(fileVersion)
        output.append(combined)
        return output
    }

    public static func decrypt(_ data: Data, keyData: Data) throws -> VaultPayload {
        guard data.count > magic.count + 1, data.prefix(magic.count) == magic else {
            throw VaultCryptoError.invalidFile
        }

        let versionIndex = data.index(data.startIndex, offsetBy: magic.count)
        guard data[versionIndex] == fileVersion else {
            throw VaultCryptoError.unsupportedFormat
        }

        let encryptedStart = data.index(after: versionIndex)
        let sealedBox = try AES.GCM.SealedBox(combined: data[encryptedStart...])
        let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(VaultPayload.self, from: plaintext)
        } catch let error as VaultPayloadError {
            switch error {
            case .unsupportedFormat:
                throw VaultCryptoError.unsupportedFormat
            }
        }
    }
}
