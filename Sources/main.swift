// PodPointer – use an AirPods charging case as an air mouse on macOS.
//
// The earbuds stay inside the open case. Their IMU (via CMHeadphoneMotionManager)
// therefore reports the case's own rotation, which is turned into cursor motion;
// a finger tap on the case shows up as an acceleration spike and becomes a click.

import AppKit

let config = Config.parse()
L10n.configure(override: config.language)

let app = NSApplication.shared
let delegate = AppDelegate(cfg: config)
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
