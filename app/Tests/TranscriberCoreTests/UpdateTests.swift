import CryptoKit
import XCTest
@testable import TranscriberCore

/// The three places an updater goes wrong: it orders versions as strings, it
/// believes a feed it should have refused, or it installs a zip it did not
/// check. Each has a test here.
final class UpdateTests: XCTestCase {

    // MARK: - Versions

    func testParsesOneToFourComponentsAndALeadingV() {
        XCTAssertEqual(AppVersion("1.2")?.components, [1, 2])
        XCTAssertEqual(AppVersion("1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(AppVersion("v1.2.3.4")?.components, [1, 2, 3, 4])
        XCTAssertEqual(AppVersion(" 1.1.0 ")?.components, [1, 1, 0])
    }

    func testRefusesVersionsItCannotOrder() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion("1.2.x"))
        XCTAssertNil(AppVersion("1.2.3.4.5"))
        // A truncated pre-release would compare equal to the final build and
        // could install over it.
        XCTAssertNil(AppVersion("1.2.0-rc1"))
    }

    func testOrdersByComponentNotByString() {
        XCTAssertTrue(AppVersion("1.2.0")! < AppVersion("1.11.0")!)
        XCTAssertTrue(AppVersion("1.9.0")! < AppVersion("1.10.0")!)
        XCTAssertTrue(AppVersion("1.1.0")! < AppVersion("2.0.0")!)
        XCTAssertFalse(AppVersion("2.0.0")! < AppVersion("1.11.9")!)
    }

    func testTrailingZerosAreNotSignificant() {
        XCTAssertEqual(AppVersion("1.2")!, AppVersion("1.2.0")!)
        XCTAssertEqual(AppVersion("1.2")!.hashValue, AppVersion("1.2.0.0")!.hashValue)
        XCTAssertNotEqual(AppVersion("1.2")!, AppVersion("1.2.1")!)
    }

    // MARK: - The feed

    private func feed(_ entries: String) -> Data { Data("[\(entries)]".utf8) }

    private func entry(tag: String,
                       draft: Bool = false,
                       prerelease: Bool = false,
                       assets: [String] = ["Transcriber.zip", "Transcriber.zip.sig"]) -> String {
        let list = assets.map {
            """
            {"name":"\($0)","browser_download_url":"https://example.test/\($0)","size":10}
            """
        }.joined(separator: ",")
        return """
        {"tag_name":"\(tag)","name":"Transcriber \(tag)","body":"notes",
         "draft":\(draft),"prerelease":\(prerelease),
         "published_at":"2026-09-04T12:00:00Z",
         "html_url":"https://example.test/\(tag)","assets":[\(list)]}
        """
    }

    func testReadsAReleaseAndItsAssets() throws {
        let releases = try ReleaseFeed.releases(from: feed(entry(tag: "v1.2.0")))
        XCTAssertEqual(releases.count, 1)
        let release = try XCTUnwrap(releases.first)
        XCTAssertEqual(release.version, AppVersion("1.2.0"))
        XCTAssertEqual(release.title, "Transcriber v1.2.0")
        XCTAssertEqual(release.notes, "notes")
        XCTAssertEqual(release.appZip?.name, "Transcriber.zip")
        XCTAssertEqual(release.signature?.name, "Transcriber.zip.sig")
        XCTAssertTrue(release.isInstallable)
        XCTAssertNotNil(release.publishedAt)
    }

    func testDropsDraftsPrereleasesAndUnreadableTags() throws {
        let data = feed([
            entry(tag: "v1.2.0", draft: true),
            entry(tag: "v1.3.0", prerelease: true),
            entry(tag: "nightly"),
            entry(tag: "v1.1.0"),
        ].joined(separator: ","))
        let releases = try ReleaseFeed.releases(from: data)
        XCTAssertEqual(releases.map(\.version), [AppVersion("1.1.0")])
    }

    func testAReleaseWithNoSignatureIsNotInstallable() throws {
        let data = feed(entry(tag: "v1.2.0", assets: ["Transcriber.zip"]))
        let release = try XCTUnwrap(try ReleaseFeed.releases(from: data).first)
        XCTAssertNotNil(release.appZip)
        XCTAssertNil(release.signature)
        XCTAssertFalse(release.isInstallable)
    }

    func testRubbishIsRefusedRatherThanDecodedEmpty() {
        XCTAssertThrowsError(try ReleaseFeed.releases(from: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? UpdateError, .unreadableFeed)
        }
    }

    // MARK: - The choice

    func testOffersTheNewestInstallableReleaseAboveTheCurrentOne() throws {
        let data = feed([
            entry(tag: "v1.1.0"),
            entry(tag: "v1.3.0"),
            entry(tag: "v1.2.0"),
        ].joined(separator: ","))
        let releases = try ReleaseFeed.releases(from: data)
        let choice = UpdateCheck.newest(in: releases, after: AppVersion("1.1.0")!)
        XCTAssertEqual(choice?.version, AppVersion("1.3.0"))
    }

    func testOffersNothingAtOrAboveTheNewestRelease() throws {
        let releases = try ReleaseFeed.releases(from: feed(entry(tag: "v1.1.0")))
        XCTAssertNil(UpdateCheck.newest(in: releases, after: AppVersion("1.1.0")!))
        XCTAssertNil(UpdateCheck.newest(in: releases, after: AppVersion("1.2.0")!))
    }

    func testNeverWalksBackwardsAndNeverOffersAnUnsignedRelease() throws {
        let data = feed([
            entry(tag: "v0.9.0"),
            entry(tag: "v2.0.0", assets: ["Transcriber.zip"]),
        ].joined(separator: ","))
        let releases = try ReleaseFeed.releases(from: data)
        XCTAssertNil(UpdateCheck.newest(in: releases, after: AppVersion("1.1.0")!))
    }

    func testASkippedVersionIsNotOfferedAgain() throws {
        let data = feed([entry(tag: "v1.2.0"), entry(tag: "v1.3.0")].joined(separator: ","))
        let releases = try ReleaseFeed.releases(from: data)
        let choice = UpdateCheck.newest(in: releases,
                                        after: AppVersion("1.1.0")!,
                                        skipping: AppVersion("1.3.0"))
        XCTAssertEqual(choice?.version, AppVersion("1.2.0"))
    }

    // MARK: - Signatures

    func testSignatureFileRoundTrips() throws {
        let original = ReleaseSignature(sha256: Data(repeating: 0xAB, count: 32),
                                        signature: Data(repeating: 0xCD, count: 64))
        let parsed = try ReleaseSignature.parse(original.fileContents)
        XCTAssertEqual(parsed, original)
    }

    func testMalformedSignatureFilesAreRefused() {
        let good = ReleaseSignature(sha256: Data(repeating: 1, count: 32),
                                    signature: Data(repeating: 2, count: 64))
        let fields = good.fileContents.split(separator: " ")
        for text in [
            "",
            "wrong-magic \(fields[1]) \(fields[2])",
            "\(ReleaseSignature.magic) \(fields[1])",
            "\(ReleaseSignature.magic) abcd \(fields[2])",             // digest too short
            "\(ReleaseSignature.magic) \(fields[1]) notbase64!!",
            "\(ReleaseSignature.magic) \(fields[1]) \(Data(repeating: 3, count: 8).base64EncodedString())",
        ] {
            XCTAssertThrowsError(try ReleaseSignature.parse(text), text) { error in
                XCTAssertEqual(error as? UpdateError, .malformedSignature)
            }
        }
    }

    /// A file, the signature the private key makes over it, and the public key.
    private func signedFile(bytes: Data = Data("a release".utf8))
        throws -> (url: URL, signature: ReleaseSignature, publicKey: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-\(UUID().uuidString).zip")
        try bytes.write(to: url)
        let key = Curve25519.Signing.PrivateKey()
        let digest = try UpdateVerifier.sha256(ofFileAt: url)
        let signature = ReleaseSignature(sha256: digest,
                                         signature: try key.signature(for: digest))
        return (url, signature, key.publicKey.rawRepresentation.base64EncodedString())
    }

    func testAcceptsAFileTheKeyHolderSigned() throws {
        let (url, signature, key) = try signedFile()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNoThrow(try UpdateVerifier.verify(fileAt: url, against: signature, publicKey: key))
    }

    func testStreamedDigestMatchesTheWholeFileDigest() throws {
        // Larger than the 1 MB read window, so a chunking mistake shows.
        let bytes = Data((0..<(3 * (1 << 20) + 7)).map { UInt8($0 % 251) })
        let (url, _, _) = try signedFile(bytes: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try UpdateVerifier.sha256(ofFileAt: url), Data(SHA256.hash(data: bytes)))
    }

    func testRefusesAFileThatChangedAfterSigning() throws {
        let (url, signature, key) = try signedFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("a different release".utf8).write(to: url)
        XCTAssertThrowsError(try UpdateVerifier.verify(fileAt: url, against: signature, publicKey: key)) {
            XCTAssertEqual($0 as? UpdateError, .damagedDownload)
        }
    }

    func testRefusesAFileSignedByAnotherKey() throws {
        let (url, signature, _) = try signedFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let stranger = Curve25519.Signing.PrivateKey().publicKey
            .rawRepresentation.base64EncodedString()
        XCTAssertThrowsError(try UpdateVerifier.verify(fileAt: url, against: signature, publicKey: stranger)) {
            XCTAssertEqual($0 as? UpdateError, .wrongSignature)
        }
    }

    /// The digest and the signature are both in the file. Restating the digest
    /// must not be enough to pass: the signature is over the digest, so a
    /// forged pair has to break the curve, not the format.
    func testARewrittenDigestDoesNotLetAForgedFileThrough() throws {
        let (url, signature, key) = try signedFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("a tampered release".utf8).write(to: url)
        let forged = ReleaseSignature(sha256: try UpdateVerifier.sha256(ofFileAt: url),
                                      signature: signature.signature)
        XCTAssertThrowsError(try UpdateVerifier.verify(fileAt: url, against: forged, publicKey: key)) {
            XCTAssertEqual($0 as? UpdateError, .wrongSignature)
        }
    }

    func testABuildWithNoKeyRefusesToVerifyAnything() throws {
        let (url, signature, _) = try signedFile()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try UpdateVerifier.verify(fileAt: url, against: signature, publicKey: "")) {
            XCTAssertEqual($0 as? UpdateError, .noPublicKey)
        }
    }

    // MARK: - Hex

    func testHexRoundTripsAndRefusesRubbish() {
        let bytes = Data([0x00, 0x0f, 0xa5, 0xff])
        XCTAssertEqual(bytes.hexString, "000fa5ff")
        XCTAssertEqual(Data(hex: "000fa5ff"), bytes)
        XCTAssertNil(Data(hex: "abc"))
        XCTAssertNil(Data(hex: "zz"))
    }
}
