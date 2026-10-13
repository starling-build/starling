#if canImport(Testing)
import Testing
#endif

#if canImport(XCTest)


import XCTest
import OfficeAppPackageDiscoveredTests
#endif

@main
@available(macOS 10.15, iOS 11, watchOS 4, tvOS 11, *)
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
struct Runner {
    private static func testingLibrary() -> String {
        var iterator = CommandLine.arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "--testing-library", let libraryName = iterator.next() {
                return libraryName.lowercased()
            }
        }

        // Fallback if not specified: run XCTest (legacy behavior)
        return "xctest"
    }

    #if false
    @_silgen_name("$ss13_runAsyncMainyyyyYaKcF")
    private static func _runAsyncMain(_ asyncFun: @Sendable @escaping () async throws -> ())
    #endif

    static func main() async {
        let testingLibrary = Self.testingLibrary()
        #if canImport(Testing)
        if testingLibrary == "swift-testing" {
            #if false
            _runAsyncMain {
                await Testing.__swiftPMEntryPoint() as Never
            }
            #else
            await Testing.__swiftPMEntryPoint() as Never
            #endif
        }
        #endif
        #if canImport(XCTest)
        if testingLibrary == "xctest" {
            
             XCTMain(__allDiscoveredTests()) as Never
        }
        #endif
    }
}