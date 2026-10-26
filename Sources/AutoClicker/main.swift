import AppKit
import AutoClickCore
import ServiceManagement
import SwiftUI

if CommandLine.arguments.contains("--diagnose") {
    let configuration = UserDefaults.standard.data(forKey: "clickConfiguration")
        .flatMap { try? JSONDecoder().decode(ClickConfiguration.self, from: $0) } ?? .init()
    var details: [String: Any] = [
        "bundlePath": Bundle.main.bundleURL.path,
        "bundleIdentifier": Bundle.main.bundleIdentifier ?? "unbundled",
        "accessibilityGranted": AXIsProcessTrusted(),
        "loginItemStatus": SMAppService.mainApp.status.rawValue,
        "loginItemStatusLegend": "0 = not registered, 1 = enabled, 2 = requires approval, 3 = not found",
        "configuration": [
            "clickDelayMilliseconds": configuration.clickDelayMilliseconds,
            "clicksPerBurst": configuration.clicksPerBurst,
            "burstPauseMilliseconds": configuration.burstPauseMilliseconds,
            "startDelayMilliseconds": configuration.startDelayMilliseconds
        ]
    ]
    let request = UUID().uuidString
    var response: [AnyHashable: Any]?
    let observer = DistributedNotificationCenter.default().addObserver(
        forName: Notification.Name("local.kevin.autoclicker.diagnosticResponse"), object: request, queue: .main
    ) { response = $0.userInfo }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("local.kevin.autoclicker.diagnose"), object: request, userInfo: nil, deliverImmediately: true
    )
    let deadline = Date().addingTimeInterval(0.5)
    while response == nil && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.01)))
    }
    DistributedNotificationCenter.default().removeObserver(observer)
    if let response { details["runningApplication"] = response }
    let data = try JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

let application = NSApplication.shared

if CommandLine.arguments.contains("--self-test") {
    application.setActivationPolicy(.prohibited)
    exit(RuntimeChecks.run())
}

if let index = CommandLine.arguments.firstIndex(of: "--render-preview"),
   CommandLine.arguments.indices.contains(index + 1) {
    application.setActivationPolicy(.prohibited)
    let model = AppModel(preview: true)
    let view = NSHostingView(rootView: ControlsView(model: model, close: {}))
    let size = view.fittingSize
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.contentView = view
    view.frame = NSRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    print("Rendered \(Int(size.width)) × \(Int(size.height)) preview")
    exit(0)
}

if let identifier = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("local.kevin.autoclicker.showControls"), object: nil,
        userInfo: nil, deliverImmediately: true
    )
    exit(0)
}

let delegate = AppDelegate()
application.delegate = delegate
application.run()
