// The release signing key, and the signatures the updater checks.
//
// Compiled together with ../Sources/TranscriberCore/Update.swift, so the file
// format here and the parser in the app are one piece of code. `Update.swift`
// imports only Foundation and CryptoKit, which is what makes that possible.
//
//     swiftc -O -o relkey scripts/relkey.swift Sources/TranscriberCore/Update.swift
//
//     relkey generate            make the key pair (refuses to overwrite)
//     relkey public              print the public key to paste into Update.swift
//     relkey sign FILE           write FILE.sig
//     relkey verify FILE BASE64  check FILE.sig against a public key
//
// The private key is a file, mode 0600, outside the repository:
//
//     ~/.config/transcriber/release-key        (or $TRANSCRIBER_RELEASE_KEY)
//
// Back it up. Every installed copy of the app carries the matching public key,
// so losing this file means no installed copy can accept another update; they
// all have to be replaced by hand.

import CryptoKit
import Foundation

let keyURL: URL = {
    if let override = ProcessInfo.processInfo.environment["TRANSCRIBER_RELEASE_KEY"] {
        return URL(fileURLWithPath: override)
    }
    return URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".config/transcriber/release-key")
}()

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("relkey: \(message)\n".utf8))
    exit(1)
}

func loadPrivateKey() -> Curve25519.Signing.PrivateKey {
    guard let text = try? String(contentsOf: keyURL, encoding: .utf8) else {
        die("no signing key at \(keyURL.path). Run `relkey generate` first.")
    }
    guard let bytes = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: bytes) else {
        die("the key at \(keyURL.path) is not a base64 Ed25519 private key.")
    }
    return key
}

func generate() {
    if FileManager.default.fileExists(atPath: keyURL.path) {
        die("a key already exists at \(keyURL.path). Delete it by hand if you really "
            + "mean to replace it -- every installed copy of the app refuses updates "
            + "signed by the new one until it is replaced by hand.")
    }
    let directory = keyURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    let text = key.rawRepresentation.base64EncodedString() + "\n"
    guard FileManager.default.createFile(atPath: keyURL.path,
                                         contents: Data(text.utf8),
                                         attributes: [.posixPermissions: 0o600]) else {
        die("could not write \(keyURL.path).")
    }
    print("wrote \(keyURL.path) (mode 0600). Back it up somewhere safe.")
    print("")
    print("Put this line in Sources/TranscriberCore/Update.swift:")
    print("")
    print("    public static let publicKey = \"\(key.publicKey.rawRepresentation.base64EncodedString())\"")
}

func sign(_ path: String) {
    let url = URL(fileURLWithPath: path)
    let key = loadPrivateKey()
    do {
        let digest = try UpdateVerifier.sha256(ofFileAt: url)
        let signature = ReleaseSignature(sha256: digest, signature: try key.signature(for: digest))
        let out = URL(fileURLWithPath: path + ReleaseSignature.fileSuffix)
        try Data(signature.fileContents.utf8).write(to: out)
        print("signed \(url.lastPathComponent) -> \(out.lastPathComponent)")
        print("sha256 \(digest.hexString)")
    } catch {
        die("could not sign \(path): \(error.localizedDescription)")
    }
}

func verify(_ path: String, _ publicKey: String) {
    let url = URL(fileURLWithPath: path)
    do {
        let text = try String(contentsOf: URL(fileURLWithPath: path + ReleaseSignature.fileSuffix),
                              encoding: .utf8)
        try UpdateVerifier.verify(fileAt: url,
                                  against: try ReleaseSignature.parse(text),
                                  publicKey: publicKey)
        print("ok: \(url.lastPathComponent) matches its signature and that key")
    } catch {
        die("\(url.lastPathComponent) did NOT verify: \(error.localizedDescription)")
    }
}

// `@main` rather than top-level code: this file is compiled alongside
// Update.swift, and only a file named main.swift may hold statements.
@main
enum Relkey {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "generate":
            generate()
        case "public":
            print(loadPrivateKey().publicKey.rawRepresentation.base64EncodedString())
        case "sign":
            guard arguments.count == 2 else { die("usage: relkey sign FILE") }
            sign(arguments[1])
        case "verify":
            guard arguments.count == 3 else { die("usage: relkey verify FILE PUBLIC_KEY_BASE64") }
            verify(arguments[1], arguments[2])
        default:
            print("usage: relkey generate | public | sign FILE | verify FILE PUBLIC_KEY_BASE64")
            exit(arguments.isEmpty ? 1 : 0)
        }
    }
}
