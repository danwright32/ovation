import Testing

/// These assert the property that makes the unhosted test target work at all:
/// the app's own sources are COMPILED INTO this bundle rather than reached
/// through a launched host. If somebody later gives this target a TEST_HOST and
/// drops the compiled-in sources, it stops building rather than quietly
/// verifying nothing (L98).
struct OvationBuildTests {
    @Test("the app module's own types are reachable from the unhosted suite")
    func appModuleIsCompiledIn() {
        #expect(OvationBuild.displayName == "Ovation")
    }

    @Test("the one window carries a single named identity, not two spellings")
    func mainWindowIdentityIsNamed() {
        // Plan 1.13's menu bar item and URL handler both bring THIS window
        // forward. Two spellings of the identifier would silently open a second
        // window, and PRD 41b's single window assertion would then be false
        // while every model level test still passed.
        #expect(OvationBuild.mainWindowID == "ovation.main")
        #expect(!OvationBuild.mainWindowID.isEmpty)
    }
}
