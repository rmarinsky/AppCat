import AppKit
import Foundation

private struct ReceiverState: Codable {
    var isReady = false
    var mouseDownCount = 0
    var openRequestCount = 0
    var activationCount = 0
}

private struct ReceiverConfiguration: Decodable {
    let statePath: String
    let routerAppPath: String
    let routedURLString: String

    var stateURL: URL { URL(fileURLWithPath: statePath) }
    var routerAppURL: URL { URL(fileURLWithPath: routerAppPath) }
    var routedURL: URL? { URL(string: routedURLString) }
}

@MainActor
private final class ReceiverStateStore {
    private let fileURL: URL
    private var state = ReceiverState()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func markReady() {
        state.isReady = true
        persist()
    }

    func recordMouseDown() {
        state.mouseDownCount += 1
        persist()
    }

    func recordOpenRequest() {
        state.openRequestCount += 1
        persist()
    }

    func recordActivation() {
        state.activationCount += 1
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
private final class ReceiverView: NSView {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with _: NSEvent) {
        onMouseDown?()
    }
}

@MainActor
private final class ReceiverAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var stateStore: ReceiverStateStore?
    private var routerAppURL: URL?
    private var routedURL: URL?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func application(_: NSApplication, open urls: [URL]) {
        if stateStore == nil,
           let configurationURL = urls.first,
           let data = try? Data(contentsOf: configurationURL),
           let configuration = try? JSONDecoder().decode(ReceiverConfiguration.self, from: data),
           let routedURL = configuration.routedURL
        {
            configure(with: configuration, routedURL: routedURL)
            return
        }

        stateStore?.recordOpenRequest()
    }

    private func configure(with configuration: ReceiverConfiguration, routedURL: URL) {
        stateStore = ReceiverStateStore(fileURL: configuration.stateURL)
        routerAppURL = configuration.routerAppURL
        self.routedURL = routedURL

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let receiverView = ReceiverView(frame: NSRect(origin: .zero, size: screenFrame.size))
        receiverView.wantsLayer = true
        receiverView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        receiverView.onMouseDown = { [weak self] in
            self?.recordClickThroughAndRouteAgain()
        }

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = receiverView
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(screenFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        stateStore?.markReady()
    }

    func applicationDidBecomeActive(_: Notification) {
        stateStore?.recordActivation()
    }

    private func recordClickThroughAndRouteAgain() {
        stateStore?.recordMouseDown()
        guard let routerAppURL, let routedURL else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [routedURL],
            withApplicationAt: routerAppURL,
            configuration: configuration
        )
    }
}

@main
@MainActor
private enum ReceiverApplication {
    private static let delegate = ReceiverAppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.run()
    }
}
