import Foundation
import Testing
@testable import Ovation

/// One predicate answers "may this launch touch anything real", and these hold it
/// to both directions of that question. A guard that can only ever answer "not
/// real" is indistinguishable from one that is working (L159), so the false case
/// is asserted in the same file as the true ones.
struct AppEnvironmentTests {
    @Test("an XCTest configuration file marks the launch disposable")
    func configurationFilePathIsDetected() {
        #expect(AppEnvironment.isDisposableLaunch(
            environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
    }

    @Test("an XCTest bundle path marks the launch disposable")
    func bundlePathIsDetected() {
        #expect(AppEnvironment.isDisposableLaunch(
            environment: ["XCTestBundlePath": "/tmp/OvationTests.xctest"]))
    }

    @Test("an XCTest session identifier marks the launch disposable")
    func sessionIdentifierIsDetected() {
        #expect(AppEnvironment.isDisposableLaunch(
            environment: ["XCTestSessionIdentifier": "ABC-123"]))
    }

    @Test("a launch carrying none of them is not disposable")
    func aPlainLaunchIsNotDisposable() {
        // The positive control. Without it, every assertion above is satisfied by
        // a predicate that answers true to everything.
        #expect(!AppEnvironment.isDisposableLaunch(environment: [:]))
        #expect(!AppEnvironment.isDisposableLaunch(environment: ["HOME": "/Users/someone"]))
    }

    @Test("the default argument reads THIS process, so a caller that passes nothing is still refused")
    func theDefaultIsWiredToTheRealEnvironment() {
        // This suite IS a test process. A predicate whose default argument were an
        // empty dictionary would pass every case above and answer false here, and
        // every path resolver defaulting to it would then hand a test the real
        // path (L188: the value the configuration sets is not the value in force).
        #expect(AppEnvironment.isDisposableLaunch())
    }
}
