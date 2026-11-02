import Foundation
import Testing
@testable import Radiology

/// Language-specific positive and negative detection of test-only regions,
/// from real parses. Regions are compared as one-based inclusive line spans.
struct TestRegionDetectorTests {
    private func detect(_ source: String, path: String) async throws -> (SyntaxSnapshot, SourceBuffer, [ClosedRange<Int>]) {
        let buffer = try SourceBuffer(path: path, data: Data(source.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        let lines = snapshot.testRegions.map { region in
            buffer.line(atByte: region.byteRange.lowerBound)...buffer.line(atByte: max(region.byteRange.lowerBound, region.byteRange.upperBound - 1))
        }
        return (snapshot, buffer, lines)
    }

    @Test func pytestRequiresUnderscoreAndVitestElseRemainsProduction() async throws {
        let python = """
        import pytest
        def testing_helper(): pass
        def testify(): pass
        def testConnection(): pass
        def test_connection(): pass
        """
        let (_, _, lines) = try await detect(python, path: "api.py")
        #expect(lines == [5...5])
        let ts = """
        if (import.meta.vitest) {
          test('x', () => {});
        } else {
          production();
        }
        """
        let (syntax, _, _) = try await detect(ts, path: "api.ts")
        #expect(syntax.testRegions.isEmpty, "a production alternative conservatively keeps the entire if visible")
    }

    @Test func rustTestHelperInTheMiddleOfAnImplEndsExactlyBeforeProductionCode() async throws {
        // tkos app.rs:802–834 in miniature: no blank line separates the test
        // helper's closing brace from the next production method.
        let source = """
        impl HarnessApp {
            #[cfg(test)]
            pub(crate) fn detached_for_test(
                engine: Arc<Engine>,
            ) -> Arc<Self> {
                Arc::new(Self { engine })
            }
            fn create_durable_agent(&self) -> u8 {
                1
            }
        }
        """
        let (_, buffer, lines) = try await detect(source, path: "app.rs")
        #expect(lines == [2...7])
        let region = try #require(try await SyntaxWorker().parse(buffer)?.testRegions.first)
        #expect(region.evidence == .cfgTest)
        // The newline after `}` stays outside, so line 8 keeps its own line.
        #expect(buffer.data[region.byteRange.upperBound] == 0x0A)
        #expect(String(decoding: buffer.data[region.byteRange], as: UTF8.self).hasPrefix("    #[cfg(test)]"))
        #expect(String(decoding: buffer.data[region.byteRange], as: UTF8.self).hasSuffix("    }"))
    }

    @Test func rustCfgLogicHidesOnlyCodeAbsentFromEveryProductionBuild() async throws {
        let source = """
        #[cfg(test)]
        mod tests;
        #[cfg(all(test, feature = "x"))]
        fn all_test() {}

        #[cfg(any(test, feature = "prod"))]
        fn shared_with_production() {}
        #[cfg(not(test))]
        fn production_only() {}
        #[cfg_attr(test, derive(Debug))]
        struct Traced;
        #[cfg(any())]
        fn disabled() {}
        #[cfg(feature = "test")]
        fn feature_named_test() {}
        fn contest() {}
        fn test_connection() {}
        #[cfg(any(test, doctest))]
        fn doctest_helper() {}
        """
        let (_, _, lines) = try await detect(source, path: "lib.rs")
        // 1–4 merge across the blank-free gap; 18–19 is separate.
        #expect(lines == [1...4, 18...19])
    }

    @Test func rustTestAttributesModulesDocCommentsAndInnerAttributes() async throws {
        let source = """
        pub fn production() {}

        /// Builds a fixture.
        #[test]
        #[should_panic]
        fn panics() {}
        #[tokio::test(flavor = "multi_thread")]
        async fn async_case() {}
        #[rstest]
        fn parameterized(#[values(1, 2)] value: u8) {}
        // A production comment.
        pub fn after() {}
        mod inner {
            #![cfg(test)]
            fn helper() {}
        }
        #[derive(Debug)]
        #[cfg(test)] // trailing note
        struct Probe {
            #[cfg(test)]
            counter: usize,
        }
        """
        let (_, _, lines) = try await detect(source, path: "lib.rs")
        #expect(lines == [3...10, 13...22])
    }

    @Test func rustFileWithInnerCfgTestIsATestOnlyDocument() async throws {
        let (snapshot, _, lines) = try await detect("//! Tests.\n#![cfg(test)]\nfn a() {}\n", path: "tests.rs")
        #expect(snapshot.isTestOnlyDocument)
        #expect(lines.isEmpty)
    }

    @Test func rustRegionsUseCanonicalBytesAfterUnicodeAndCRLF() async throws {
        let source = "// 🩻 胸部\r\nfn a() {}\r\n#[cfg(test)]\r\nmod t {\r\n    fn é() {}\r\n}\r\nfn b() {}\r\n"
        let (_, buffer, lines) = try await detect(source, path: "u.rs")
        #expect(lines == [3...6])
        let region = try #require(try await SyntaxWorker().parse(buffer)?.testRegions.first)
        // The region ends before the CR of the CRLF terminator.
        #expect(buffer.data[region.byteRange.upperBound] == 0x0D)
        #expect(String(decoding: buffer.data[region.byteRange], as: UTF8.self) == "#[cfg(test)]\r\nmod t {\r\n    fn é() {}\r\n}")
    }

    @Test func kotlinTestClassesFunctionsAndSpecs() async throws {
        let source = """
        package inc.tk

        import org.junit.Test

        class Production {
            fun test(): Int = 1
            @Deprecated("x") fun old() {}
        }

        class FontFilesTest {
            private val bytes = byteArrayOf(0)

            @Test fun `downloads once`() {
                println(bytes)
            }
        }

        @RunWith(JUnit4::class)
        class Runner { fun helper() {} }

        class CalculatorSpec : StringSpec({
            "adds" { }
        })

        fun production() {}
        /** KDoc for a test. */
        @org.junit.jupiter.api.Test
        fun qualified() {}
        fun after() {}
        """
        let (_, _, lines) = try await detect(source, path: "Mixed.kt")
        #expect(lines == [10...23, 26...28])
    }

    @Test func pythonUnittestClassesAndPytestOnlyWhenImported() async throws {
        let production = """
        import unittest

        def test_connection(host):
            return True

        class TestHarness:
            pass

        class PrLocalTest(unittest.TestCase):
            def test_a(self):
                pass

        class Runner(object):
            pass
        """
        let (_, _, productionLines) = try await detect(production, path: "pr_local.py")
        #expect(productionLines == [9...11])

        let pytest = """
        import os, pytest

        @pytest.fixture
        def repo():
            return 1

        def helper():
            return 2

        async def test_async(repo):
            pass
        class TestThings:
            def test_x(self):
                pass

        @pytest.mark.parametrize("n", [1])
        def check(n):
            pass
        """
        let (_, _, pytestLines) = try await detect(pytest, path: "conftest_like.py")
        // 10–14 and 16–18 are separated only by a blank line, so they merge.
        #expect(pytestLines == [3...5, 10...18])
    }

    @Test func typescriptFrameworkCallsAndInSourceBlocks() async throws {
        let source = """
        import { test, expect } from 'bun:test';
        import { summaryReport } from './home-design-inspect.ts';

        export function report() { return summaryReport(); }

        test('text contrast', () => {
          expect(1).toBe(1);
        });

        describe.each([1, 2])('case %s', (n) => {
          it('works', () => {});
        });
        if (import.meta.vitest) {
          const { it } = import.meta.vitest;
          it('inline', () => {});
        }
        Deno.test("deno", () => {});
        """
        let (_, _, lines) = try await detect(source, path: "home-design-inspect.test.ts")
        #expect(lines == [6...17])
    }

    @Test func typescriptProductionCallsSharingTestSpellingStayVisible() async throws {
        let source = """
        import { test } from './regex';
        const it = makeIterator();
        function describe(value: unknown) { return String(value); }

        test('pattern', () => true);
        it('x', () => {});
        describe(() => 1);
        suite.add('benchmark');
        beforeEach;
        """
        let (_, _, lines) = try await detect(source, path: "regex.ts")
        #expect(lines.isEmpty)
    }

    @Test func tsxAndCommonJSRequireFromTestModules() async throws {
        let tsx = """
        import { render } from './render';
        export const View = () => <div>{render()}</div>;
        it('renders', () => {
          expect(<View />).toBeTruthy();
        });
        """
        let (_, _, tsxLines) = try await detect(tsx, path: "View.tsx")
        #expect(tsxLines == [3...5])

        let commonJS = """
        const { describe, it } = require('node:test');
        const test = require('./not-a-test-runner');
        describe('suite', () => { it('case', () => {}); });
        test('production', function () {});
        """
        let (_, _, jsLines) = try await detect(commonJS, path: "suite.js")
        #expect(jsLines == [3...3])
    }

    @Test func deeplyNestedGeneratedCodeIsWalkedWithoutRecursion() async throws {
        let depth = 4_000
        let source = "fn generated() -> i32 { " + String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth)
            + " }\n#[cfg(test)]\nmod tests {}\n"
        let (_, _, lines) = try await detect(source, path: "generated.rs")
        #expect(lines == [2...3])
    }

    @Test func languagesWithoutDetectionReportNothing() async throws {
        let (snapshot, _, lines) = try await detect("func TestX(t *testing.T) {}\n", path: "x_test.go")
        #expect(lines.isEmpty)
        #expect(!snapshot.isTestOnlyDocument)
    }
}
