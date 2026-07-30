import AppKit
import SwiftUI

struct LivePreview: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat
    let fade: CGFloat
    let opacity: CGFloat
    let showsIdleIndicator: Bool

    func makeNSView(context: Context) -> StripVisualizationView {
        let view = StripVisualizationView(width: width, height: height)
        view.showsIdleIndicator = showsIdleIndicator
        StripRegistry.shared.register(view)
        return view
    }

    func updateNSView(_ view: StripVisualizationView, context: Context) {
        view.resize(width: width, height: height)
        view.fadeWidth = fade
        view.opacity = opacity
        view.mode = NowseeSettings.shared.visualization
        view.apply(palette: NowseeSettings.shared.palette)
    }
}

struct PaletteSwatch: View {
    let palette: Palette

    var body: some View {
        LinearGradient(
            colors: palette.stops.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) },
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 96, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct SettingsView: View {
    @Bindable var settings = NowseeSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                preview
                Divider()
                visualizationSection
                Divider()
                windowSection
                Divider()
                menuBarSection
            }
            .padding(22)
            .frame(width: 460, alignment: .leading)
        }
        .frame(width: 460, height: 640)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.headline)
            LivePreview(
                width: 416, height: 96, fade: 0, opacity: 1, showsIdleIndicator: false
            )
            .frame(height: 96)
            .background(Color.black.opacity(settings.windowOpacity))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("Menu bar").font(.subheadline).foregroundStyle(.secondary)
            LivePreview(
                width: settings.barWidth,
                height: 22,
                fade: settings.barFade,
                opacity: settings.barOpacity,
                showsIdleIndicator: true
            )
            .frame(width: settings.barWidth, height: 22)
        }
    }

    private var visualizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visualization").font(.headline)

            Picker("Type", selection: $settings.visualization) {
                ForEach(Visualization.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(
                "Waveform and Ocean skip the FFT entirely — they reduce the signal to a min/max "
                    + "envelope, so they cost less than the spectrogram."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if settings.visualization.usesEnvelope {
                slider(
                    "Sensitivity", value: $settings.waveformGain, range: 1...30,
                    display: String(format: "%.1f×", settings.waveformGain))
                Text("Most music peaks well below full scale, so a gain above 1 is usually needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Palette").font(.subheadline)
                ForEach(Palette.all, id: \.name) { option in
                    HStack {
                        Image(systemName: settings.paletteName == option.name ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(settings.paletteName == option.name ? Color.accentColor : .secondary)
                        Text(option.name).frame(width: 70, alignment: .leading)
                        PaletteSwatch(palette: option)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { settings.paletteName = option.name }
                }
            }

            Picker("Frame rate", selection: $settings.frameRate) {
                ForEach(NowseeSettings.frameRateOptions, id: \.self) { rate in
                    Text("\(rate) fps").tag(rate)
                }
            }
        }
    }

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window").font(.headline)
            Toggle("Float above all other windows", isOn: $settings.alwaysOnTop)
            slider(
                "Background opacity", value: $settings.windowOpacity, range: 0...1,
                display: "\(Int(settings.windowOpacity * 100))%")
        }
    }

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Menu Bar").font(.headline)
            slider(
                "Width", value: $settings.barWidth, range: 40...220,
                display: "\(Int(settings.barWidth)) pt")
            slider(
                "Edge fade", value: $settings.barFade, range: 0...30,
                display: "\(Int(settings.barFade)) px")
            slider(
                "Opacity", value: $settings.barOpacity, range: 0.2...1,
                display: "\(Int(settings.barOpacity * 100))%")
        }
    }

    private func slider(
        _ label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String
    ) -> some View {
        HStack {
            Text(label).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range)
            Text(display).frame(width: 52, alignment: .trailing).monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
