import SwiftUI

/// The custom dark popover panel, styled after the captain's preferred "Left"
/// menu-bar app: a rounded dark panel, a clean header (glyph + name + muted
/// status, a small pill top-right), generous spacing, and a subtle footer.
///
/// Two pages live here — the tiny front panel and a Settings page — switched by
/// local state, so the whole thing stays a single transient popover.
struct PanelView: View {
    @ObservedObject var model: AppModel
    var quit: () -> Void

    @State private var page: Page = .front
    private enum Page { case front, settings }

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .front:
                FrontPage(model: model, openSettings: { withAnimation(.easeInOut(duration: 0.15)) { page = .settings } })
            case .settings:
                SettingsPage(model: model,
                             back: { withAnimation(.easeInOut(duration: 0.15)) { page = .front } },
                             quit: quit)
            }
        }
        .frame(width: 288)
        .background(Color.black.opacity(0.001))   // let the popover's dark material show
        .onAppear { model.refresh() }
    }
}

// MARK: - Front page

private struct FrontPage: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: glyph + name + status, gear pill top-right.
            HStack(alignment: .center, spacing: 10) {
                FilterGlyph().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Color Filter")
                        .font(.system(size: 14, weight: .semibold))
                    Text(model.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: openSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            Divider().opacity(0.5)

            // Primary control: Run / Pause. The one thing.
            RunPauseButton(model: model)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            // Location — shown, tap to edit (editor lives in Settings).
            Button(action: openSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Location")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(model.locationSummary)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .padding(.bottom, 6)
    }
}

private struct RunPauseButton: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button(action: { model.toggleRun() }) {
            HStack(spacing: 8) {
                Image(systemName: model.filterOn ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(model.filterOn ? "Pause" : "Run")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(model.filterOn ? "Filter on" : "Filter off")
                    .font(.system(size: 11))
                    .foregroundStyle(model.filterOn ? Color.white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(model.filterOn
                          ? AnyShapeStyle(LinearGradient(colors: [Color.orange, Color.pink],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.primary.opacity(0.08)))
            )
            .foregroundStyle(model.filterOn ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings page

private struct SettingsPage: View {
    @ObservedObject var model: AppModel
    var back: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: back + title.
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Text("Settings").font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 18) {
                StrengthControl(model: model)
                LocationControl(model: model)
                AutomaticControl(model: model)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 14)

            Divider().opacity(0.5)

            Button(action: quit) {
                HStack(spacing: 7) {
                    Image(systemName: "power").font(.system(size: 11))
                    Text("Quit").font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.vertical, 11)
        }
    }
}

private struct StrengthControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Strength").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int((model.strength * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { model.strength },
                                  set: { model.setStrength($0) }),
                   in: 0...1)
            .controlSize(.small)
        }
    }
}

private struct LocationControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Location").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("latitude, longitude")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                TextField("Lat", text: $model.latitudeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12)).monospacedDigit()
                    .multilineTextAlignment(.center)
                TextField("Lon", text: $model.longitudeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12)).monospacedDigit()
                    .multilineTextAlignment(.center)
                Button("Set") { model.applyLocation() }
                    .controlSize(.regular)
            }
            .onSubmit { model.applyLocation() }
        }
    }
}

private struct AutomaticControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { model.automationEnabled },
                                 set: { model.setAutomation($0) })) {
                Text("Automatic").font(.system(size: 12, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Text("Follow the sun — filter on from sunset to sunrise.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Evidence rendering (offscreen; never touches the live filter)

/// Renders the front and settings pages to PNGs for documentation. It builds a
/// throwaway model and assigns display values in-memory only — it never calls
/// the engine setters, so the captain's live Color Filters state is untouched.
enum PanelEvidence {
    @MainActor
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Temporarily seed a location in THIS binary's defaults (isolated from the
        // installed app's domain) so the shots aren't empty; restored afterwards.
        let savedLat = Settings.shared.latitude, savedLon = Settings.shared.longitude
        Settings.shared.latitude = 38.72; Settings.shared.longitude = -9.14
        defer { Settings.shared.latitude = savedLat; Settings.shared.longitude = savedLon }

        let onModel = AppModel()
        onModel.filterOn = true
        onModel.strength = 0.62
        onModel.automationEnabled = false
        onModel.latitudeText = "38.72"; onModel.longitudeText = "-9.14"
        onModel.statusText = "On"

        let offModel = AppModel()
        offModel.filterOn = false
        offModel.automationEnabled = true
        offModel.latitudeText = "38.72"; offModel.longitudeText = "-9.14"
        offModel.statusText = "Off · auto"

        save(FrontPage(model: onModel, openSettings: {}), "\(dir)/panel-front-running.png")
        save(FrontPage(model: offModel, openSettings: {}), "\(dir)/panel-front-paused.png")
        save(SettingsPage(model: onModel, back: {}, quit: {}), "\(dir)/panel-settings.png")
        MenuBarIcon.writeEvidence(to: "\(dir)/menubar-icon-light-dark.png")
        print("wrote panel evidence -> \(dir)")
    }

    /// Render via the real AppKit path (NSHostingView in an offscreen dark
    /// window + cacheDisplay) so NSSlider/NSTextField/switch draw as they do
    /// live — unlike ImageRenderer, which stubs AppKit-backed controls.
    @MainActor
    private static func save<V: View>(_ view: V, _ path: String) {
        let wrapped = view
            .frame(width: 288)
            .background(Color(nsColor: NSColor(calibratedRed: 0.14, green: 0.13, blue: 0.16, alpha: 1)))

        let host = NSHostingView(rootView: wrapped)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.displayIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

// MARK: - Brand glyph (color-filter / day–night)

/// A small circle, half tinted with a warm→cool gradient — reads as a color
/// filter and as day/night. Used decoratively in the header.
struct FilterGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.55), lineWidth: 1.4)
                Circle()
                    .fill(LinearGradient(colors: [Color.orange, Color.indigo],
                                         startPoint: .top, endPoint: .bottom))
                    .mask(
                        Rectangle().frame(width: d / 2, height: d)
                            .offset(x: d / 4)
                    )
            }
            .frame(width: d, height: d)
        }
    }
}
