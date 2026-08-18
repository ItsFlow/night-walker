import AppKit

// Headless CLI mode (testing/scripting) short-circuits before the GUI starts.
if let code = CLI.run(CommandLine.arguments) {
    exit(code)
}

// Otherwise run as a menu-bar-only agent.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Agent (menu-bar only) even when run as a bare binary; the bundled app also
// sets LSUIElement=true in its Info.plist.
app.setActivationPolicy(.accessory)
app.run()
