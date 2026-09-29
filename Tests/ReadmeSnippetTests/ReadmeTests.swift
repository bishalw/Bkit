import Foundation
import Testing

/// Keeps README.md honest. Every ```swift block in it must appear, whitespace aside, in one of
/// the snippet files beside this one, which this target compiles; so a README example that
/// stops compiling, or is edited without its snippet, fails here. Blocks fenced
/// ```swift manifest are Package.swift fragments, which a test target can't compile; they are
/// checked against the package's products and the changelog's version instead.
@Suite("README")
struct ReadmeTests {
    private static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    private static let packageRoot = directory.deletingLastPathComponent().deletingLastPathComponent()

    @Test func everySwiftBlockIsCompiledInThisTarget() throws {
        let blocks = try Self.blocks(fencedAs: "swift")
        #expect(blocks.count >= 10, "found only \(blocks.count) swift blocks; is the README's fence format still ```swift?")
        let snippets = try FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "ReadmeTests.swift" }
            .map { Self.normalized(try String(contentsOf: $0, encoding: .utf8)) }
        for block in blocks {
            let text = Self.normalized(block)
            #expect(snippets.contains { $0.contains(text) }, "This README block isn't in Tests/ReadmeSnippetTests:\n\(block)")
        }
    }

    @Test func theInstallBlocksNameRealProductsAndTheReleasedVersion() throws {
        let install = try Self.blocks(fencedAs: "swift manifest").joined(separator: "\n")
        let manifest = try String(contentsOf: Self.packageRoot.appending(path: "Package.swift"), encoding: .utf8)
        let changelog = try String(contentsOf: Self.packageRoot.appending(path: "CHANGELOG.md"), encoding: .utf8)

        let products = install.matches(of: #/\.product\(name: "([^"]+)"/#).map { String($0.output.1) }
        #expect(!products.isEmpty)
        for product in products {
            #expect(manifest.contains(#".library(name: "\#(product)""#), "\(product) isn't a product in Package.swift")
        }
        let version = try #require(install.firstMatch(of: #/from: "([^"]+)"/#)).output.1
        let released = try #require(changelog.firstMatch(of: #/\n## (\S+)/#)).output.1
        #expect(version == released, "the README installs \(version) but the changelog's latest is \(released)")
    }

    /// The contents of every fenced block whose info string is exactly `info`.
    private static func blocks(fencedAs info: String) throws -> [String] {
        let readme = try String(contentsOf: packageRoot.appending(path: "README.md"), encoding: .utf8)
        var blocks: [String] = []
        var lines: [Substring] = []
        var openFence: String?  // the info string of the block being read
        for line in readme.split(separator: "\n", omittingEmptySubsequences: false) {
            if let fence = openFence {
                if line.hasPrefix("```") {
                    if fence == info { blocks.append(lines.joined(separator: "\n")) }
                    openFence = nil
                    lines = []
                } else {
                    lines.append(line)
                }
            } else if line.hasPrefix("```") {
                openFence = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            }
        }
        return blocks
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
