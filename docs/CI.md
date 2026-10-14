# CI runtime policy

Normal pushes run all 26 domain tests directly with host SwiftPM; they do not boot iOS or launch the application. Sources are taken from the Xcode domain-test target in project.yml, including future tests.

Pull requests also compile the iOS app using a generic simulator destination without launching a simulator. Main compiles the application once, in the existing Release archive and signing workflow, after domain tests pass. A green iOS build on main means domain validation; deployment has its own compilation/signing result.

UI regression tests remain available through Run workflow → ui_tests: shopping, preparation, drag, or all. Run the relevant suite for interaction changes and all for broader shopping-flow changes. This is an explicit tradeoff: routine main releases are not gated by simulator UI tests. Do not claim UI coverage for a host-only run.

Ordinary CI creates no screenshot or result-bundle uploads. Manual UI runs export screenshots; the large xcresult bundle is uploaded only on failure. Cancelled runs skip artifact work. New pushes cancel obsolete validation runs. Apple processing continues to use an Ubuntu runner rather than occupy a Mac.

Measure runtime from completed jobs before promising a fixed minute saving. Simulator boot and debugger launch were the dominant delays in the October 14 runs; the domain assertions themselves took about 0.1 seconds. No tests have been deleted or assertions weakened.
