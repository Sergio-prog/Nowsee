import AppKit
import MetalKit
import SwiftUI

private final class VisualizerWindow: NSWindow {
    var onToggleFrame: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if key == "f", modifiers == [.command, .shift] {
            onToggleFrame?()
            return true
        }
        if key == "f", modifiers == [.command, .control] {
            toggleFullScreen(nil)
            return true
        }
        if key == "w", modifiers == .command {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
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
    private var frameMenuItem: NSMenuItem!
    private var isPaused = false
    private var isVisualizerFramed = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Nowsee must keep capturing while its windows are closed")
        setUpStatusItem()

        engine.visualization = settings.visualization
        engine.onColumn = { [weak self] column in
            if self?.isVisualizerActive == true {
                self?.renderer?.append(column: column)
            }
            StripRegistry.shared.broadcast(column: column)
            self?.wakeRendererIfNeeded()
        }
        engine.onEnvelope = { [weak self] low, high in
            if self?.isVisualizerActive == true {
                self?.renderer?.append(low: low, high: high)
            }
            StripRegistry.shared.broadcast(low: low, high: high)
            self?.wakeRendererIfNeeded()
        }
        engine.onSpectrumBands = { [weak self] levels in
            if self?.isVisualizerActive == true {
                self?.renderer?.update(spectrum: levels)
            }
            StripRegistry.shared.broadcast(spectrum: levels)
            self?.wakeRendererIfNeeded()
        }
        engine.onStatus = { [weak self] status in
            self?.statusMenuItem.title = status
        }
        engine.onReconfigure = { [weak self] reason in
            self?.writeDiagnostic("tap rebuilt — \(reason)")
        }
        engine.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged),
            name: .nowseeSettingsChanged, object: nil)

        applySettings()

        let idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let renderer = self.renderer, !self.isPaused else { return }
            if renderer.hasScrolledToSilence, !self.settings.standby.animates,
                self.metalView?.isPaused == false
            {
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
        if selfTests.contains("reconfigure") {
            for delay in [5.0, 9.0, 13.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.engine.simulateReconfiguration()
                }
            }
        }
        if selfTests.contains("settings") || selfTests.contains("settings-close") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showSettings()
            }
        }
        if selfTests.contains("settings-close") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.settingsWindow?.performClose(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.showSettings()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.settingsWindow?.performClose(nil)
            }
        }
        if selfTests.contains("window-controls") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showWindow()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.toggleWindowFrame()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.toggleWindowFrame()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.window?.performClose(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.deminiaturize(nil)
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            showWindow()
        }
        return true
    }

    private func wakeRendererIfNeeded() {
        guard metalView?.isPaused == true, window?.isVisible == true, !isPaused,
            renderer?.hasScrolledToSilence == false
        else { return }
        metalView?.isPaused = false
    }

    private var isVisualizerActive: Bool {
        window?.isVisible == true && window?.isMiniaturized == false
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
        frameMenuItem = NSMenuItem(
            title: "Hide Window Frame", action: #selector(toggleWindowFrame), keyEquivalent: "f")
        frameMenuItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(frameMenuItem)
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
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateWindowMenuItems()
    }

    private func setUpWindow() {
        guard window == nil else { return }
        guard
            let renderer = SpectrogramRenderer(
                rowCount: AudioEngine.rowCount, bandCount: AudioEngine.bandCount)
        else {
            statusMenuItem?.title = "Metal unavailable"
            return
        }
        self.renderer = renderer

        let requested = ProcessInfo.processInfo.environment["NOWSEE_WINDOW"]?
            .split(separator: "x").compactMap { Double($0) } ?? []
        let size = requested.count == 2 ? NSSize(width: requested[0], height: requested[1])
            : NSSize(width: 900, height: 320)
        let view = MTKView(
            frame: NSRect(origin: .zero, size: size), device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.sampleCount = SpectrogramRenderer.sampleCount
        view.delegate = renderer
        view.layer?.isOpaque = false
        metalView = view

        let window = VisualizerWindow(
            contentRect: view.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nowsee"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 320, height: 120)
        if requested.count == 2 || !window.setFrameUsingName("NowseeVisualizer") {
            window.center()
        }
        window.setFrameAutosaveName("NowseeVisualizer")
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
        window.onToggleFrame = { [weak self] in self?.toggleWindowFrame() }
        view.isPaused = true
        self.window = window
    }

    @objc private func settingsChanged() {
        applySettings()
    }

    private func applySettings() {
        engine.visualization = settings.visualization
        updateProcessingRate()
        engine.smoothing = Float(settings.smoothing)
        renderer?.mode = settings.visualization
        renderer?.apply(palette: settings.palette)
        renderer?.background = SIMD4(0, 0, 0, Float(settings.windowOpacity))
        renderer?.gain = Float(settings.waveformGain)
        renderer?.shape = SIMD4(
            Float(settings.equalizerBarCount), Float(settings.equalizerBarGap),
            Float(settings.smoothing), 0)
        renderer?.standbyStyle = StandbyAnimation.allCases.firstIndex(of: settings.standby) ?? 0
        renderer?.standbyIntensity = Float(settings.standbyIntensity)
        renderer?.standbyTint = baselineTintForWindow()
        if settings.standby.animates, window?.isVisible == true {
            metalView?.isPaused = false
        }

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
        PreviewSignal.shared.applySettings()
    }

    private func baselineTintForWindow() -> SIMD4<Float> {
        let color =
            settings.baselineMatchesSystem
            ? NSColor.tertiaryLabelColor.withAlphaComponent(1) : settings.baselineNSColor
        let resolved = color.usingColorSpace(.sRGB) ?? .white
        let alpha = settings.baselineMatchesSystem ? 0.26 : 1.0
        return SIMD4(
            Float(resolved.redComponent), Float(resolved.greenComponent),
            Float(resolved.blueComponent), Float(alpha * settings.baselineOpacity))
    }

    @objc private func showWindow() {
        setUpWindow()
        applySettings()
        metalView?.isPaused = false
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleWindowFrame() {
        if window?.isVisible != true {
            showWindow()
        }
        guard let window else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }

        isVisualizerFramed.toggle()
        let masks: NSWindow.StyleMask = isVisualizerFramed
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.borderless, .closable, .resizable]
        window.styleMask = masks
        window.isMovableByWindowBackground = !isVisualizerFramed
        window.title = "Nowsee"
        window.makeKeyAndOrderFront(nil)
        updateWindowMenuItems()
    }

    private func updateWindowMenuItems() {
        frameMenuItem?.title = isVisualizerFramed ? "Hide Window Frame" : "Show Window Frame"
        let isFullScreen = window?.styleMask.contains(.fullScreen) == true
        frameMenuItem?.isEnabled = !isFullScreen
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let contentSize = NSSize(width: 540, height: 620)
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.preferredContentSize = contentSize
            hosting.view.frame = NSRect(origin: .zero, size: contentSize)

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: contentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.title = "Settings"
            // AppKit still owns close-animation state during windowWillClose. Keep the
            // window and its SwiftUI hosting tree alive so that state cannot outlive them.
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 500, height: 520)
            if !window.setFrameUsingName("NowseeSettings") {
                window.setContentSize(contentSize)
                window.center()
            }
            window.setFrameAutosaveName("NowseeSettings")
            window.delegate = self
            settingsWindow = window
        }
        Task { @MainActor in LaunchAtLoginController.shared.refresh() }
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow {
            PreviewSignal.shared.attach(to: settingsWindow)
        }

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
        let closing = notification.object as? NSWindow
        if closing === settingsWindow {
            PreviewSignal.shared.detach()
        }
        if closing === window {
            metalView?.isPaused = true
            updateProcessingRate()
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        metalView?.isPaused = true
        updateProcessingRate()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        metalView?.isPaused = false
        updateProcessingRate()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        updateWindowMenuItems()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        updateWindowMenuItems()
    }

    private func updateProcessingRate() {
        let visualizerRate = window?.isVisible == true && window?.isMiniaturized == false
            ? settings.frameRate : 0
        engine.frameRate = max(settings.menuBarFrameRate, visualizerRate)
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
                \(StripRegistry.shared.activitySummary) \
                mock=\(PreviewSignal.shared.isRunning) host=\(PreviewSignal.shared.hasHost) \
                paused=\(self.isPaused) \
                status=\(self.statusMenuItem.title)
                """)
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
