import AppKit
import SwiftUI

struct LivePreview: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat
    let fade: CGFloat
    let opacity: CGFloat
    let showsIdleIndicator: Bool
    var backgroundOpacity: CGFloat = 0
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> StripVisualizationView {
        let view = StripVisualizationView(width: width, height: height)
        view.showsIdleIndicator = showsIdleIndicator
        view.isPreview = true
        StripRegistry.shared.register(view)
        PreviewSignal.shared.applySettings()
        return view
    }

    func updateNSView(_ view: StripVisualizationView, context: Context) {
        view.resize(width: width, height: height)
        view.fadeWidth = fade
        view.opacity = opacity
        view.backgroundOpacity = backgroundOpacity
        view.cornerRadius = cornerRadius
        view.mode = NowseeSettings.shared.visualization
        view.apply(palette: NowseeSettings.shared.palette)
    }

    static func dismantleNSView(_ view: StripVisualizationView, coordinator: ()) {
        StripRegistry.shared.unregister(view)
        PreviewSignal.shared.applySettings()
    }
}

private struct PaletteSwatch: View {
    let palette: Palette

    var body: some View {
        LinearGradient(
            colors: palette.stops.map {
                Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z))
            },
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case visualizer
    case menuBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .visualizer: return "Visualizer"
        case .menuBar: return "Menu Bar"
        }
    }
}

struct SettingsView: View {
    @Bindable private var settings = NowseeSettings.shared
    @Bindable private var launchAtLogin = LaunchAtLoginController.shared
    @State private var page: SettingsPage = .general

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch page {
                    case .general: generalPage
                    case .visualizer: visualizerPage
                    case .menuBar: menuBarPage
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 500, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Text("Nowsee")
                .font(.title2.weight(.semibold))
            Spacer()
            Picker("Section", selection: $page) {
                ForEach(SettingsPage.allCases) { page in
                    Text(page.title).tag(page)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeading(
                "General",
                detail: "Choose how Nowsee behaves when you open it and while it is running."
            )

            section("Startup") {
                Toggle(
                    "Launch Nowsee when you log in",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .disabled(launchAtLogin.isUpdating)

                if launchAtLogin.needsApproval {
                    helpText(
                        "macOS needs approval. Enable Nowsee in System Settings › General › Login Items."
                    )
                } else if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else {
                    helpText("Starts quietly in the menu bar; no window opens automatically.")
                }
            }

            section("Visualizer window") {
                Toggle("Keep above other windows", isOn: $settings.alwaysOnTop)
                slider(
                    "Background opacity", value: $settings.windowOpacity, range: 0...1,
                    display: percent(settings.windowOpacity))
                helpText(
                    "Use ⌘⇧F to hide or restore the standard window frame. Press ⌘W to close it."
                )
            }
        }
    }

    private var visualizerPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeading(
                "Visualizer",
                detail: "Tune the shape, colour and motion shared by the window and menu bar."
            )
            visualizerPreview

            section("Style") {
                Picker("Type", selection: $settings.visualization) {
                    ForEach(Visualization.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                helpText(settings.visualization.detail)

                if settings.visualization.usesGain {
                    slider(
                        "Sensitivity", value: $settings.waveformGain, range: 1...30,
                        display: String(format: "%.1f×", settings.waveformGain))
                }
                if settings.visualization == .bars {
                    slider(
                        "Bars", value: $settings.equalizerBarCount, range: 8...96,
                        display: "\(Int(settings.equalizerBarCount))")
                    slider(
                        "Bar spacing", value: $settings.equalizerBarGap, range: 0...0.6,
                        display: percent(settings.equalizerBarGap))
                }
                if settings.visualization.usesSmoothing {
                    slider(
                        "Smoothing", value: $settings.smoothing, range: 0...1,
                        display: percent(settings.smoothing))
                    helpText(smoothingDetail)
                }
            }

            section("Palette") {
                paletteGrid
                if settings.paletteName == Palette.customName {
                    HStack(spacing: 20) {
                        ColorPicker(
                            "Low", selection: customBinding(\.customLow), supportsOpacity: false)
                        ColorPicker(
                            "Mid", selection: customBinding(\.customMid), supportsOpacity: false)
                        ColorPicker(
                            "High", selection: customBinding(\.customHigh), supportsOpacity: false)
                    }
                }
            }

            section("Standby") {
                Picker("When silent", selection: $settings.standby) {
                    ForEach(StandbyAnimation.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                helpText(settings.standby.detail)

                if settings.standby.animates {
                    slider(
                        "Intensity", value: $settings.standbyIntensity, range: 0...1,
                        display: percent(settings.standbyIntensity))
                }

                Toggle("Match system appearance", isOn: $settings.baselineMatchesSystem)
                if !settings.baselineMatchesSystem {
                    ColorPicker(
                        "Baseline colour", selection: customBinding(\.baselineColor),
                        supportsOpacity: false)
                }
                slider(
                    "Baseline opacity", value: $settings.baselineOpacity, range: 0...1,
                    display: percent(settings.baselineOpacity))
            }

            section("Performance") {
                Picker("Window frame rate", selection: $settings.frameRate) {
                    frameRateOptions
                }
                helpText("Lower frame rates use less CPU and energy while the window is open.")
            }

            Toggle("Animate this preview when audio is quiet", isOn: $settings.mockPreview)
        }
    }

    private var menuBarPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            pageHeading(
                "Menu Bar",
                detail: "Keep the always-visible strip readable without spending more energy than it needs."
            )
            menuBarPreview

            section("Appearance") {
                slider(
                    "Width", value: $settings.barWidth, range: 40...220,
                    display: "\(Int(settings.barWidth)) pt")
                slider(
                    "Edge fade", value: $settings.barFade, range: 0...30,
                    display: "\(Int(settings.barFade)) px")
                slider(
                    "Opacity", value: $settings.barOpacity, range: 0.2...1,
                    display: percent(settings.barOpacity))
            }

            section("Performance") {
                Picker("Menu bar frame rate", selection: $settings.menuBarFrameRate) {
                    frameRateOptions
                }
                helpText(
                    "This strip is always visible and is Nowsee’s largest ongoing CPU cost. "
                        + "15 fps is recommended; 30 fps is smoother."
                )
            }

            Toggle("Animate this preview when audio is quiet", isOn: $settings.mockPreview)
        }
    }

    private var visualizerPreview: some View {
        GeometryReader { geometry in
            LivePreview(
                width: geometry.size.width, height: 108, fade: 0, opacity: 1,
                showsIdleIndicator: false, backgroundOpacity: settings.windowOpacity,
                cornerRadius: 8
            )
        }
        .frame(height: 108)
    }

    private var menuBarPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))
            LivePreview(
                width: settings.barWidth, height: 22, fade: settings.barFade,
                opacity: settings.barOpacity, showsIdleIndicator: true
            )
            .frame(width: settings.barWidth, height: 22)
        }
        .frame(height: 58)
    }

    private var paletteGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Palette.all, id: \.name) { option in
                let selected = settings.paletteName == option.name
                Button {
                    settings.paletteName = option.name
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                        Text(option.name)
                            .frame(width: 66, alignment: .leading)
                        PaletteSwatch(palette: option)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
    }

    private func pageHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var frameRateOptions: some View {
        ForEach(NowseeSettings.frameRateOptions, id: \.self) { rate in
            Text("\(rate) fps").tag(rate)
        }
    }

    private var smoothingDetail: String {
        settings.visualization == .ocean
            ? "Softens the swell so the surface rolls instead of spiking."
            : "Blends neighbouring bands and slows their movement."
    }

    private func percent(_ value: Double) -> String { "\(Int(value * 100))%" }

    private func slider(
        _ label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String
    ) -> some View {
        HStack {
            Text(label).frame(width: 142, alignment: .leading)
            Slider(value: value, in: range)
            Text(display)
                .frame(width: 58, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func customBinding(_ path: ReferenceWritableKeyPath<NowseeSettings, SIMD3<Float>>)
        -> Binding<Color>
    {
        Binding(
            get: {
                let value = settings[keyPath: path]
                return Color(red: Double(value.x), green: Double(value.y), blue: Double(value.z))
            },
            set: { newValue in
                guard let components = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                settings[keyPath: path] = SIMD3(
                    Float(components.redComponent), Float(components.greenComponent),
                    Float(components.blueComponent))
            }
        )
    }
}
