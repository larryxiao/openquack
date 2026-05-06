import XCTest
@testable import OpenQuackKit

final class PolishEngineTests: XCTestCase {
    func testPolishContextRoundTripsAllFields() {
        let now = Date()
        let ctx = PolishContext(
            language: "en",
            foregroundApp: "Cursor",
            timestamp: now
        )
        XCTAssertEqual(ctx.language, "en")
        XCTAssertEqual(ctx.foregroundApp, "Cursor")
        XCTAssertEqual(ctx.timestamp, now)
    }

    func testPolishContextDefaults() {
        let ctx = PolishContext()
        XCTAssertNil(ctx.language)
        XCTAssertNil(ctx.foregroundApp)
    }

    func testPolishEngineKindRawValuesAreStable() {
        XCTAssertEqual(PolishEngineKind.off.rawValue, "off")
        XCTAssertEqual(PolishEngineKind.ollama.rawValue, "ollama")
        XCTAssertEqual(PolishEngineKind.mlxLM.rawValue, "mlx-lm")
    }

    func testPolishEngineKindAllCasesIsExhaustive() {
        let all = Set(PolishEngineKind.allCases)
        XCTAssertEqual(all, [.off, .ollama, .mlxLM])
    }

    func testPolishErrorIsLocalized() {
        let cases: [PolishError] = [
            .notConfigured,
            .modelNotLoaded("gemma3:1b"),
            .timeout,
            .backendUnavailable("connection refused"),
            .decodingFailed,
        ]
        for err in cases {
            XCTAssertNotNil(err.errorDescription, "\(err) should have localized description")
        }
    }

    /// Compile-time check that any well-formed implementer satisfies the
    /// protocol. Real engines (`OllamaPolishEngine`, `MLXLMPolishEngine`)
    /// land in subsequent SPEC-007 PRs; this stub keeps the contract
    /// honest before they exist.
    func testProtocolCompilesWithMinimalImplementer() async throws {
        final class StubEngine: TextPolishEngine {
            static let engineName = "stub"
            let requiresNetwork = false
            let modelLabel = "stub"
            func polish(_ raw: String, context: PolishContext) async throws -> String {
                raw
            }
        }
        let engine = StubEngine()
        let polished = try await engine.polish("hello", context: PolishContext())
        XCTAssertEqual(polished, "hello")
    }
}
