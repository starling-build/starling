import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("OfficeApp_OfficeApp.resources").path
        let buildPath = "C:\\Users\\starling\\dev\\starling\\apps\\OfficeApp\\.build-test\\x86_64-unknown-windows-msvc\\release\\OfficeApp_OfficeApp.resources"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}