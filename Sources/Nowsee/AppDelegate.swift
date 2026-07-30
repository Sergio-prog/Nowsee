import AppKit
import MetalKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let engine = AudioEngine()
    private let settings = NowseeSettings.shared

    private var statusItem: NSStatusItem!
    private var menuBarStrip: StripVisualizationView!
    private var renderer: SpectrogramRenderer?
    private var window: NSWindow?
    private var metalView: MTKView?
    private var settingsWindow: NSWindow?
    private var statusMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var isPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpWindow()

        engine.visualization = settings.visualization
        engine.onColumn = { [weak self] column in
            self?.renderer?.append(column: column)
            StripRegistry.shared.broadcast(column: column)
            self?.wakeRendererIfNeeded()
        }
        engine.onEnvelope = { [weak self] low, high in
            self?.renderer?.append(low: low, high: high)
            StripRegistry.shared.broadcast(low: low, high: high)
            self?.wakeRendererIfNeeded()
        }
        engine.onScope = { [weak self] bounds, trace in
            self?.renderer?.update(bounds: bounds, trace: trace)
            StripRegistry.shared.broadcast(bounds: bounds, trace: trace)
            self?.wakeRendererIfNeeded()
        }
        engine.onStatus = { [weak self] status in
            self?.statusMenuItem.title = status
        }
        engine.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .nowseeSettingsChanged, object: nil)

        applySettings()

        let idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let renderer = self.renderer, !self.isPaused else { return }
            if renderer.hasScrolledToSilence, self.metalView?.isPaused == false {
                self.metalView?.isPaused = true
            }
        }
        RunLoop.main.add(idleTimer, forMode: .common)

        if ProcessInfo.processInfo.environment["NOWSEE_DIAGNOSTICS"] == "1" {
            startDiagnostics()
        }
        let selfTests = Set(
            (ProcessInfo.processInfo.environment["NOWSEE_SELFTEST"] ?? "")
                .split(separator: ",").map(String.init))

        if selfTests.contains("signal") {
            engine.startSyntheticSignal()
        }
        if selfTests.contains("settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    private func wakeRendererIfNeeded() {
        guard metalView?.isPaused == true, window?.isVisible == true, !isPaused,
            renderer?.hasScrolledToSilence == false
        else { return }
        metalView?.isPaused = false
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: settings.barWidth)
        menuBarStrip = StripVisualizationView(width: settings.barWidth, height: 22)
        StripRegistry.shared.register(menuBarStrip)

        if let button = statusItem.button {
            menuBarStrip.frame = button.bounds
            menuBarStrip.autoresizingMask = [.width, .height]
            button.addSubview(menuBarStrip)
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Show Visualizer", action: #selector(showWindow), keyEquivalent: "s"))
        pauseMenuItem = NSMenuItem(
            title: "Pause Capture", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(pauseMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Nowsee", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func setUpWindow() {
        guard
            let renderer = SpectrogramRenderer(
                rowCount: AudioEngine.rowCount, scopeColumns: AudioEngine.scopeColumns)
        else {
            statusMenuItem?.title = "Metal unavailable"
            return
        }
        self.renderer = renderer

        let view = MTKView(frame: NSRect(x: 0, y: 0, width: 900, height: 320), device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = renderer
        view.layer?.isOpaque = false
        metalView = view

        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nowsee"
        window.contentView = view
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.window = window

        showWindow()
    }

    @objc private func settingsChanged() {
        applySettings()
    }

    private func applySettings() {
        engine.visualization = settings.visualization
        engine.frameRate = settings.frameRate
        renderer?.mode = settings.visualization
        renderer?.apply(palette: settings.palette)
        renderer?.background = SIMD4(0, 0, 0, Float(settings.windowOpacity))
        renderer?.gain = Float(settings.waveformGain)

        metalView?.preferredFramesPerSecond = settings.frameRate
        metalView?.layer?.isOpaque = settings.windowOpacity >= 1

        window?.level = settings.alwaysOnTop ? .floating : .normal
        window?.isOpaque = settings.windowOpacity >= 1
        window?.backgroundColor = settings.windowOpacity >= 1 ? .black : .clear
        window?.hasShadow = settings.windowOpacity >= 1

        statusItem.length = settings.barWidth
        menuBarStrip.resize(width: settings.barWidth, height: 22)
        menuBarStrip.fadeWidth = settings.barFade
        menuBarStrip.opacity = settings.barOpacity

        StripRegistry.shared.applySettings()
    }

    @objc private func showWindow() {
        metalView?.isPaused = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let contentSize = NSSize(width: 460, height: 640)
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.preferredContentSize = contentSize
            hosting.view.frame = NSRect(origin: .zero, size: contentSize)

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.title = "Nowsee Settings"
            window.isReleasedWhenClosed = false
            window.setContentSize(contentSize)
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if ProcessInfo.processInfo.environment["NOWSEE_DIAGNOSTICS"] == "1" {
            logSettingsGeometry("immediately")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.logSettingsGeometry("after layout")
            }
        }
    }

    private func logSettingsGeometry(_ label: String) {
        guard let content = settingsWindow?.contentView else { return }
        writeDiagnostic(
            "settings [\(label)] class=\(type(of: content)) "
                + "content=\(content.frame.size) fitting=\(content.fittingSize) "
                + "subviews=\(content.subviews.count) "
                + "previewStrips=\(StripRegistry.shared.registeredCount)")
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        metalView?.isPaused = true
    }

    func windowDidMiniaturize(_ notification: Notification) {
        metalView?.isPaused = true
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        metalView?.isPaused = false
    }

    @objc private func togglePause() {
        isPaused.toggle()
        StripRegistry.shared.setPaused(isPaused)
        pauseMenuItem.title = isPaused ? "Resume Capture" : "Pause Capture"

        if isPaused {
            engine.stop()
            metalView?.isPaused = true
            statusMenuItem.title = "Paused"
        } else {
            engine.start()
            metalView?.isPaused = !(window?.isVisible ?? false)
        }
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }

    private var diagnosticsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/nowsee.log")
    }

    private func writeDiagnostic(_ text: String) {
        guard let handle = try? FileHandle(forWritingTo: diagnosticsURL) else { return }
        handle.seekToEndOfFile()
        handle.write((text + "\n").data(using: .utf8)!)
        try? handle.close()
    }

    private func startDiagnostics() {
        FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil)

        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.writeDiagnostic(
                """
                metal=\(self.renderer == nil ? "UNAVAILABLE" : "ok") \
                mode=\(self.settings.visualization.rawValue) \
                columns=\(self.renderer?.columnsAppended ?? 0) \
                frames=\(self.renderer?.framesDrawn ?? 0) \
                peak=\(String(format: "%.3f", self.renderer?.scopePeak ?? 0)) \
                strips=\(StripRegistry.shared.registeredCount) \
                paused=\(self.isPaused) \
                status=\(self.statusMenuItem.title)
                """)
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
