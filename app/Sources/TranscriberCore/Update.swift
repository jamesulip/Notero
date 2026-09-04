import CryptoKit
import Foundation

// Everything the updater can decide without a network, a file system or a
// window. The app target owns the download and the swap; this file owns what
// counts as a version, what counts as a release, and what counts as proof that
// a downloaded zip is the one the maintainer built.
//
// It lives in Core because all of it is testable with no models and no Mac:
// version ordering, feed parsing and signature checking are the three places
// an updater gets it wrong, and none of them need a network to test.

// MARK: - Versions

/// A marketing version, as `CFBundleShortVersionString` spells it: `1.11.0`.
///
/// Ordered by component, not by string. `1.11.0` is above `1.2.0`, which is
/// the comparison a naive string sort gets backwards and which decides whether
/// the app offers an update or silently skips one.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {

    /// One to four numbers, most significant first.
    public let components: [Int]

    /// Parses `1.2`, `1.2.3`, `1.2.3.4` and a leading `v`.
    ///
    /// A pre-release suffix (`1.2.0-rc1`) is refused rather than truncated.
    /// Truncating would make `1.2.0-rc1` equal to `1.2.0`, so a release
    /// candidate could install itself over the final build and then never
    /// update again. Release tags are plain numbers; see `docs/RELEASE.md`.
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else {
                return nil
            }
            numbers.append(value)
        }
        components = numbers
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    /// Trailing zeros are not significant: `1.2` and `1.2.0` are one version.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var significant = components
        while significant.count > 1, significant.last == 0 { significant.removeLast() }
        hasher.combine(significant)
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}

// MARK: - Releases

/// One downloadable file on a release.
public struct ReleaseAsset: Sendable, Hashable {
    public let name: String
    public let url: URL
    public let size: Int

    public init(name: String, url: URL, size: Int) {
        self.name = name
        self.url = url
        self.size = size
    }
}

/// A published release, as the app needs to read it.
public struct Release: Sendable, Hashable {
    public let version: AppVersion
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let publishedAt: Date?
    public let assets: [ReleaseAsset]

    public init(version: AppVersion,
                title: String,
                notes: String,
                pageURL: URL,
                publishedAt: Date?,
                assets: [ReleaseAsset]) {
        self.version = version
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.publishedAt = publishedAt
        self.assets = assets
    }

    /// The application bundle, zipped.
    public var appZip: ReleaseAsset? {
        assets.first { $0.name.hasSuffix(".zip") }
    }

    /// The detached signature over `appZip`, named after it.
    public var signature: ReleaseAsset? {
        guard let zip = appZip else { return nil }
        return assets.first { $0.name == zip.name + ReleaseSignature.fileSuffix }
    }

    /// A release the app can install by itself. A release that carries a zip
    /// and no signature is not one: the app refuses unsigned code rather than
    /// installing it, so offering it would only produce a failure later.
    public var isInstallable: Bool { appZip != nil && signature != nil }
}

/// Reads the JSON that the GitHub releases endpoint returns.
public enum ReleaseFeed {

    /// Decodes a releases array, keeping the published, plain-numbered ones.
    ///
    /// Drafts and pre-releases are dropped here rather than in the caller:
    /// they are the two ways a maintainer stages work in public, and neither
    /// is meant to reach an installed app.
    public static func releases(from data: Data) throws -> [Release] {
        let decoded: [Entry]
        do {
            decoded = try JSONDecoder().decode([Entry].self, from: data)
        } catch {
            throw UpdateError.unreadableFeed
        }
        return decoded.compactMap(\.release)
    }

    /// The shape of the GitHub payload. Private: nothing above this file
    /// should have to know that the version arrives as `tag_name`.
    private struct Entry: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let draft: Bool?
        let prerelease: Bool?
        let published_at: String?
        let html_url: URL
        let assets: [Asset]?

        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int?
        }

        var release: Release? {
            guard draft != true, prerelease != true else { return nil }
            guard let version = AppVersion(tag_name) else { return nil }
            return Release(
                version: version,
                title: name?.isEmpty == false ? name! : tag_name,
                notes: body ?? "",
                pageURL: html_url,
                publishedAt: published_at.flatMap(ReleaseFeed.date(from:)),
                assets: (assets ?? []).map {
                    ReleaseAsset(name: $0.name, url: $0.browser_download_url, size: $0.size ?? 0)
                }
            )
        }
    }

    /// ISO 8601 with a `Z`, which is what the endpoint sends. A date that will
    /// not parse costs the "published on" line, not the update.
    static func date(from text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
    }
}

/// Which release, if any, the app should offer.
public enum UpdateCheck {

    /// The newest installable release above `current`, ignoring `skipped`.
    ///
    /// Newest by version, not by publication date: a re-published older
    /// release must not be able to walk an installation backwards.
    public static func newest(in releases: [Release],
                              after current: AppVersion,
                              skipping skipped: AppVersion? = nil) -> Release? {
        releases
            .filter { $0.isInstallable && $0.version > current && $0.version != skipped }
            .max { $0.version < $1.version }
    }
}

// MARK: - Signatures

/// The detached signature file that sits beside the zip on a release.
///
/// One line, three fields:
///
///     transcriber-release-1 <sha256 hex> <base64 Ed25519 signature>
///
/// The digest is in the file as well as under the signature so that a
/// mismatch can say *which* check failed: a wrong digest means the download is
/// damaged, a wrong signature means it is not the maintainer's build. Those
/// two want different words in front of the user.
public struct ReleaseSignature: Equatable, Sendable {

    public static let magic = "transcriber-release-1"
    public static let fileSuffix = ".sig"

    /// 32 bytes.
    public let sha256: Data
    /// 64 bytes.
    public let signature: Data

    public init(sha256: Data, signature: Data) {
        self.sha256 = sha256
        self.signature = signature
    }

    public static func parse(_ text: String) throws -> ReleaseSignature {
        let fields = text.split(whereSeparator: \.isWhitespace)
        guard fields.count == 3, fields[0] == magic else { throw UpdateError.malformedSignature }
        guard let digest = Data(hex: String(fields[1])), digest.count == SHA256.byteCount else {
            throw UpdateError.malformedSignature
        }
        guard let bytes = Data(base64Encoded: String(fields[2])), bytes.count == 64 else {
            throw UpdateError.malformedSignature
        }
        return ReleaseSignature(sha256: digest, signature: bytes)
    }

    public var fileContents: String {
        "\(Self.magic) \(sha256.hexString) \(signature.base64EncodedString())\n"
    }
}

/// Where updates come from, and the key that says they are genuine.
public enum UpdateSource {

    public static let owner = "jamesulip"
    public static let repository = "notero"

    /// Somewhere else to read the list of releases from.
    ///
    /// The app sends no credential and never will: a token compiled into a
    /// shipped binary is a token every user of that binary holds. So the feed
    /// has to be readable by anyone. A **private** repository is not, and
    /// answers 404 to the request below.
    ///
    /// Three ways to give it a readable feed, in order of least work:
    ///
    /// 1. Make the repository public. Nothing here changes.
    /// 2. Publish the releases from a second, public repository, and put its
    ///    name in `owner` and `repository` above.
    /// 3. Host a JSON file anywhere over HTTPS and name it here. It must have
    ///    the shape the GitHub endpoint returns, which is what `ReleaseFeed`
    ///    reads; the easiest way to make one is to copy that reply.
    public static let feedOverride: URL? = nil

    /// Ten is enough to find the newest one after a burst of releases, and
    /// small enough to stay inside the unauthenticated rate limit.
    public static var releasesURL: URL {
        feedOverride
            ?? URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases?per_page=10")!
    }

    public static var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repository)/releases")!
    }

    /// The Ed25519 public key, base64, whose private half signs each release.
    ///
    /// Empty disables installing. A build with no key can still say what the
    /// newest release is and open the page, because that costs nothing and
    /// tells the truth; it must not download and run code it cannot check.
    /// `app/scripts/relkey.swift` makes the pair. See `docs/RELEASE.md`.
    public static let publicKey = "7F99ZnMoNKCXKcJyFgvtnrjQjPJAWoBdGDDR8KqxUwE="

    public static var canInstall: Bool { !publicKey.isEmpty }
}

/// Checks a downloaded zip against a release signature.
public enum UpdateVerifier {

    /// Streams the file rather than reading it whole: the bundle is about
    /// 10 MB today, but a memory target of 300 MB is not a reason to load an
    /// arbitrary download into RAM.
    public static func sha256(ofFileAt url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    /// Throws unless the file at `url` is the exact bytes the holder of the
    /// key signed. Both checks are stated separately so the caller can say
    /// which one failed.
    public static func verify(fileAt url: URL,
                              against signature: ReleaseSignature,
                              publicKey base64: String = UpdateSource.publicKey) throws {
        guard let keyBytes = Data(base64Encoded: base64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyBytes) else {
            throw UpdateError.noPublicKey
        }
        let digest = try sha256(ofFileAt: url)
        guard digest == signature.sha256 else { throw UpdateError.damagedDownload }
        guard key.isValidSignature(signature.signature, for: digest) else {
            throw UpdateError.wrongSignature
        }
    }
}

// MARK: - Errors

public enum UpdateError: Error, LocalizedError, Equatable {
    case unreadableFeed
    case malformedSignature
    case noPublicKey
    case damagedDownload
    case wrongSignature
    case unexpectedBundle(String)
    case notAnInstalledApp
    case locationNotWritable(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFeed:
            return "The list of releases could not be read."
        case .malformedSignature:
            return "The signature file on that release is not in a form this app reads."
        case .noPublicKey:
            return "This build carries no update key, so it cannot check that a "
                 + "download is genuine. Update it by hand."
        case .damagedDownload:
            return "The download does not match the release. It was damaged on the way."
        case .wrongSignature:
            return "The download is signed by the wrong key. It was not built by the "
                 + "maintainer of this app. It has not been installed."
        case .unexpectedBundle(let detail):
            return "The download does not contain the expected app. \(detail)"
        case .notAnInstalledApp:
            return "This copy is not running from an app bundle, so it cannot replace "
                 + "itself. Build it again from the repository."
        case .locationNotWritable(let path):
            return "This app is in a folder it cannot write to (\(path)). Move "
                 + "Transcriber to your Applications folder, or install the update by hand."
        }
    }
}

// MARK: - Hex

extension Data {

    /// Lowercase, no separators. Used for the digest in the signature file.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Nil unless the whole string is an even number of hex digits.
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
