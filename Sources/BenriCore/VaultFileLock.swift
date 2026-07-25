import CryptoKit
import Darwin
import Foundation

public enum VaultFileLockError: Error, LocalizedError, Equatable {
    case alreadyInUse
    case systemCallFailed(operation: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .alreadyInUse:
            return "这个 Benri 保险库已被另一个进程打开。"
        case let .systemCallFailed(operation, code):
            return "无法\(operation)：\(String(cString: strerror(code)))"
        }
    }
}

public final class VaultFileLock {
    public let lockFileURL: URL

    private let stateLock = NSLock()
    private var fileDescriptor: Int32

    private init(lockFileURL: URL, fileDescriptor: Int32) {
        self.lockFileURL = lockFileURL
        self.fileDescriptor = fileDescriptor
    }

    public static func acquire(
        forVaultAt vaultFileURL: URL,
        lockDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> VaultFileLock {
        let vaultDirectoryURL = vaultFileURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let normalizedPath = vaultDirectoryURL.path
            .precomposedStringWithCanonicalMapping
            .lowercased()
        let identity = SHA256.hash(data: Data(normalizedPath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let resolvedLockDirectoryURL = lockDirectoryURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let lockDirectoryExisted = fileManager.fileExists(
            atPath: resolvedLockDirectoryURL.path
        )
        try fileManager.createDirectory(
            at: resolvedLockDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if !lockDirectoryExisted {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: resolvedLockDirectoryURL.path
            )
        }

        let lockFileURL = resolvedLockDirectoryURL.appendingPathComponent(
            "benri-vault-\(identity).lock"
        )
        let flags = O_RDWR | O_CREAT | O_CLOEXEC | O_EXLOCK | O_NONBLOCK
        let descriptor = lockFileURL.path.withCString { path in
            Darwin.open(path, flags, S_IRUSR | S_IWUSR)
        }

        guard descriptor >= 0 else {
            let code = errno
            if code == EWOULDBLOCK || code == EAGAIN {
                throw VaultFileLockError.alreadyInUse
            }
            throw VaultFileLockError.systemCallFailed(
                operation: "打开保险库锁文件",
                code: code
            )
        }

        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            throw VaultFileLockError.systemCallFailed(
                operation: "设置保险库锁文件权限",
                code: code
            )
        }

        return VaultFileLock(
            lockFileURL: lockFileURL,
            fileDescriptor: descriptor
        )
    }

    public func release() {
        stateLock.lock()
        let descriptor = fileDescriptor
        fileDescriptor = -1
        stateLock.unlock()

        if descriptor >= 0 {
            _ = Darwin.close(descriptor)
        }
    }

    deinit {
        release()
    }
}
