import SwiftUI

/// Shared palette for the panel. Tuned near-black to match the captain's
/// preferred "Left" menu-bar app (a deep, neutral, near-black surface rather
/// than a medium grey). The Run/Pause colors are deliberately chosen to stay
/// legible even while the screen's own warm/red Color Filter is applied:
/// emerald (a cool hue) for ON never blends into a red-tinted screen the way a
/// warm orange fill did, and the label is always pure white.
enum Palette {
    /// Near-black panel body (~#111214).
    static let panel = Color(red: 0.067, green: 0.070, blue: 0.078)
    /// Hairline separators / subtle borders on the dark surface.
    static let hairline = Color.white.opacity(0.08)

    /// Run/Pause — ON (filter running): a filled emerald block.
    static let runOn = Color(red: 0.17, green: 0.70, blue: 0.44)
    static let runOnBorder = Color(red: 0.34, green: 0.88, blue: 0.58).opacity(0.55)
    static let runOnDot = Color(red: 0.80, green: 1.0, blue: 0.88)
    /// Run/Pause — OFF (filter paused): a faint, outlined neutral block.
    static let controlFill = Color.white.opacity(0.055)
    static let controlBorder = Color.white.opacity(0.10)

    /// Warm amber used only for inline warning text (not a state indicator).
    static let warn = Color(red: 0.96, green: 0.68, blue: 0.34)
}

/// The custom dark key panel, styled after the captain's preferred "Left"
/// menu-bar app: a rounded near-black panel, a clean header (glyph + name, a
/// bare gear top-right), generous spacing, and a subtle footer. The big
/// Run/Pause button — not a text subtitle — is the on/off state indicator.
///
/// Two pages live here — the tiny front panel and a Settings page — switched by
/// local state, so the whole thing stays in a single window.
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
        .background(Palette.panel)                 // near-black body, "Left"-style
        .onAppear { model.refresh() }
    }
}

// MARK: - Front page

private struct FrontPage: View {
    @ObservedObject var model: AppModel
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: glyph + name, bare settings gear top-right.
            HStack(alignment: .center, spacing: 10) {
                FilterGlyph().frame(width: 22, height: 22)
                // Just the name — the Run/Pause button below IS the state indicator.
                Text("Color Filter")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(5)
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
                    Text(model.locationDisplay)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
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

/// The one control. State is conveyed by an obvious color difference —
/// emerald filled block when the filter is ON, faint outlined block when OFF —
/// chosen so it never washes out under the screen's own warm/red Color Filter
/// (emerald is a cool hue, not the tint's hue) and so the label stays pure
/// white (always high-contrast) in both states.
private struct RunPauseButton: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let on = model.filterOn
        Button(action: { model.toggleRun() }) {
            HStack(spacing: 9) {
                Image(systemName: on ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(on ? "Pause" : "Run")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(on ? Palette.runOnDot : Color.white.opacity(0.28))
                        .frame(width: 6, height: 6)
                    Text(on ? "Filter on" : "Filter off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(on ? Color.white.opacity(0.92) : Color.white.opacity(0.45))
                }
            }
            .foregroundStyle(Color.white)   // icon + primary label: always legible
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(on ? Palette.runOn : Palette.controlFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(on ? Palette.runOnBorder : Palette.controlBorder, lineWidth: 1)
            )
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
    /// Whether the lat/long fine-tune fields start expanded (used by evidence
    /// rendering so a single screenshot shows both the city field and the
    /// retained fine-tune fields).
    var locationExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: a single back affordance; no redundant page title.
            HStack(spacing: 8) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 17) {
                StrengthControl(model: model)
                LocationControl(model: model, initiallyExpanded: locationExpanded)
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
        HStack(spacing: 10) {
            Slider(value: Binding(get: { model.strength },
                                  set: { model.setStrength($0) }),
                   in: 0...1)
            .controlSize(.small)
            .accessibilityLabel("Strength")
            Text("\(Int((model.strength * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// Location = type a city (primary, geocoded via CoreLocation) with the precise
/// lat/long fields retained as a collapsible fine-tune / offline override.
private struct LocationControl: View {
    @ObservedObject var model: AppModel
    @State private var showFineTune: Bool

    init(model: AppModel, initiallyExpanded: Bool = false) {
        self.model = model
        _showFineTune = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Primary input: type a city, resolve to coordinates.
            HStack(spacing: 8) {
                TextField("Your location", text: $model.cityText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { model.resolveCity() }
                Button(action: { model.resolveCity() }) {
                    if model.isGeocoding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Find")
                    }
                }
                .controlSize(.regular)
                .disabled(model.isGeocoding)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !model.geocodeMessage.isEmpty {
                    Text(model.geocodeMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(model.lastGeocodeOK ? Color.secondary : Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.hasLocation {
                    Text(model.locationDisplay)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(showFineTune ? "Hide lat/long" : "Lat/long") {
                    withAnimation(.easeInOut(duration: 0.12)) { showFineTune.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            }

            // Fine-tune / offline override: the precise lat/long fields, retained.
            if showFineTune {
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
            }
        }
    }
}

private struct AutomaticControl: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Toggle(isOn: Binding(get: { model.automationEnabled },
                             set: { model.setAutomation($0) })) {
            Text("Automatic").font(.system(size: 12, weight: .medium))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
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
        let savedName = Settings.shared.locationName
        Settings.shared.latitude = 38.72; Settings.shared.longitude = -9.14
        Settings.shared.locationName = "Lisbon, Portugal"
        defer {
            Settings.shared.latitude = savedLat; Settings.shared.longitude = savedLon
            Settings.shared.locationName = savedName
        }

        let onModel = AppModel()
        onModel.filterOn = true
        onModel.strength = 0.62
        onModel.automationEnabled = false
        onModel.latitudeText = "38.72"; onModel.longitudeText = "-9.14"
        onModel.cityText = "Lisbon, Portugal"
        onModel.geocodeMessage = "Lisbon, Portugal · 38.7223, -9.1393"
        onModel.lastGeocodeOK = true
        onModel.statusText = "On"

        let offModel = AppModel()
        offModel.filterOn = false
        offModel.automationEnabled = true
        offModel.latitudeText = "38.72"; offModel.longitudeText = "-9.14"
        offModel.cityText = "Lisbon, Portugal"
        offModel.geocodeMessage = "Lisbon, Portugal · 38.7223, -9.1393"
        offModel.lastGeocodeOK = true
        offModel.statusText = "Off · auto"

        save(FrontPage(model: onModel, openSettings: {}), "\(dir)/panel-front-running.png")
        save(FrontPage(model: offModel, openSettings: {}), "\(dir)/panel-front-paused.png")
        save(SettingsPage(model: onModel, back: {}, quit: {}, locationExpanded: true),
             "\(dir)/panel-settings.png")
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
            .background(Color(nsColor: NSColor(calibratedRed: 0.067, green: 0.070, blue: 0.078, alpha: 1)))

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
