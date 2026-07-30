import AppKit
import MetalKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let engine = AudioEngine()
    private var statusItem: NSStatusItem!
    private var menuBarView: MenuBarSpectrogramView!
    private var renderer: SpectrogramRenderer?
    private var window: NSWindow?
    private var metalView: MTKView?
    private var statusMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var frameRateMenu: NSMenu!
    private var isPaused = false
    private var palette = Settings.palette

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpWindow()

        engine.onColumn = { [weak self] column in
            guard let self else { return }
            self.renderer?.append(column: column)
            self.menuBarView.append(column: column)
            if self.metalView?.isPaused == true, self.window?.isVisible == true,
                !self.isPaused, self.renderer?.hasScrolledToSilence == false
            {
                self.metalView?.isPaused = false
            }
        }
        engine.onStatus = { [weak self] status in
            self?.statusMenuItem.title = status
        }
        engine.start()

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
        if ProcessInfo.processInfo.environment["NOWSEE_SELFTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.togglePause() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in self?.togglePause() }
        }
    }

    private func startDiagnostics() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/nowsee.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)

        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let line = """
                metal=\(self.renderer == nil ? "UNAVAILABLE" : "ok") \
                columns=\(self.renderer?.columnsAppended ?? 0) \
                frames=\(self.renderer?.framesDrawn ?? 0) \
                brightest=\(String(format: "%.3f", self.renderer?.brightestColumn ?? 0)) \
                paused=\(self.isPaused) \
                status=\(self.statusMenuItem.title)

                """
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 72)
        menuBarView = MenuBarSpectrogramView()

        if let button = statusItem.button {
            menuBarView.frame = button.bounds
            menuBarView.autoresizingMask = [.width, .height]
            button.addSubview(menuBarView)
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Show Spectrogram", action: #selector(showWindow), keyEquivalent: "s"))

        pauseMenuItem = NSMenuItem(
            title: "Pause Capture", action: #selector(togglePause), keyEquivalent: "p")
        menu.addItem(pauseMenuItem)

        let paletteItem = NSMenuItem(title: "Palette", action: nil, keyEquivalent: "")
        let paletteMenu = NSMenu()
        for option in Palette.all {
            let item = NSMenuItem(
                title: option.name, action: #selector(selectPalette(_:)), keyEquivalent: "")
            item.representedObject = option.name
            item.state = option.name == palette.name ? .on : .off
            paletteMenu.addItem(item)
        }
        paletteItem.submenu = paletteMenu
        menu.addItem(paletteItem)

        let frameRateItem = NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: "")
        frameRateMenu = NSMenu()
        for rate in Settings.frameRateOptions {
            let item = NSMenuItem(
                title: "\(rate) fps", action: #selector(selectFrameRate(_:)), keyEquivalent: "")
            item.tag = rate
            item.state = rate == Settings.frameRate ? .on : .off
            frameRateMenu.addItem(item)
        }
        frameRateItem.submenu = frameRateMenu
        menu.addItem(frameRateItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Nowsee", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil {
            item.target = self
        }
        for item in paletteMenu.items + frameRateMenu.items {
            item.target = self
        }
        statusItem.menu = menu
        menuBarView.apply(palette: palette)
    }

    private func setUpWindow() {
        guard let renderer = SpectrogramRenderer(rowCount: AudioEngine.rowCount) else {
            statusMenuItem?.title = "Metal unavailable"
            return
        }
        self.renderer = renderer

        renderer.apply(palette: palette)

        let view = MTKView(frame: NSRect(x: 0, y: 0, width: 900, height: 320), device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = renderer
        metalView = view
        applyFrameRate()

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
        self.window = window

        showWindow()
    }

    @objc private func showWindow() {
        metalView?.isPaused = false
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        metalView?.isPaused = true
    }

    func windowDidMiniaturize(_ notification: Notification) {
        metalView?.isPaused = true
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        metalView?.isPaused = false
    }

    @objc private func selectPalette(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String,
            let option = Palette.all.first(where: { $0.name == name })
        else { return }
        palette = option
        Settings.paletteName = option.name
        renderer?.apply(palette: option)
        menuBarView.apply(palette: option)
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }

    @objc private func togglePause() {
        isPaused.toggle()
        menuBarView.setPaused(isPaused)
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

    @objc private func selectFrameRate(_ sender: NSMenuItem) {
        Settings.frameRate = sender.tag
        applyFrameRate()
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
    }

    private func applyFrameRate() {
        let rate = Settings.frameRate
        metalView?.preferredFramesPerSecond = rate
        menuBarView.redrawInterval = 1.0 / Double(min(rate, Settings.menuBarCeiling))
    }

    @objc private func quit() {
        engine.stop()
        NSApp.terminate(nil)
    }
}
