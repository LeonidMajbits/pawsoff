#!/bin/bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

TMP_DIR="$(mktemp -d /tmp/pawsoff-core-tests.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Generate lightweight XCTest shim for environments without full Xcode.app:
cat << 'EOF' > "$TMP_DIR/TestShim.swift"
import Foundation

open class XCTestCase {
    public init() {}
    open func setUp() {}
    open func tearDown() {}
}

public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    let va = a(), vb = b()
    assert(va == vb, "XCTAssertEqual failed: \(va) != \(vb) \(msg)", file: file, line: line)
}

public func XCTAssertTrue(_ c: @autoclosure () -> Bool, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(c(), "XCTAssertTrue failed \(msg)", file: file, line: line)
}

public func XCTAssertFalse(_ c: @autoclosure () -> Bool, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(!c(), "XCTAssertFalse failed \(msg)", file: file, line: line)
}

public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    let va = a(), vb = b()
    assert(va < vb, "XCTAssertLessThan failed: \(va) >= \(vb) \(msg)", file: file, line: line)
}

public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
    let va = a(), vb = b()
    assert(va >= vb, "XCTAssertGreaterThanOrEqual failed: \(va) < \(vb) \(msg)", file: file, line: line)
}
EOF

# Copy test files and replace XCTest/PawsOffCore imports with Foundation:
python3 -c "
import re

for name in ['AppearanceTests.swift', 'InputGateTests.swift']:
    content = open('Tests/PawsOffCoreTests/' + name).read()
    content = re.sub(r'import XCTest', 'import Foundation', content)
    content = re.sub(r'@testable import PawsOffCore', '', content)
    open('$TMP_DIR/' + name, 'w').write(content)

app_methods = re.findall(r'func (test\w+)\(\)', open('$TMP_DIR/AppearanceTests.swift').read())
gate_methods = re.findall(r'func (test\w+)\(\)', open('$TMP_DIR/InputGateTests.swift').read())

runner = '''import Foundation

print(\"[PawsOffCore] Executing core policy test suite...\")
let app = AppearanceTests()
'''
for m in app_methods:
    runner += f'app.{m}()\n'
runner += f'print(\"  -> Passed {len(app_methods)} AppearanceTests\")\n'

runner += '''let gate = InputGateTests()
'''
for m in gate_methods:
    runner += f'gate.{m}()\n'
runner += f'print(\"  -> Passed {len(gate_methods)} InputGateTests\")\n'
runner += f'print(\"[PawsOffCore] All {len(app_methods) + len(gate_methods)} tests passed cleanly.\")\n'

open('$TMP_DIR/main.swift', 'w').write(runner)
"

# Compile and run the standalone test runner:
xcrun swiftc Sources/PawsOffCore/*.swift "$TMP_DIR/TestShim.swift" "$TMP_DIR/AppearanceTests.swift" "$TMP_DIR/InputGateTests.swift" "$TMP_DIR/main.swift" -o "$TMP_DIR/runner"
"$TMP_DIR/runner"
