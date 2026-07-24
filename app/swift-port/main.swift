import AppKit

// حالت‌های خط فرمان بدون UI
let argv = CommandLine.arguments
if let i = argv.firstIndex(of: "--selftest"), argv.count > i + 1 {
    let lang = argv.count > i + 2 ? argv[i + 2] : "en-US"
    exit(SelfTest.run(file: argv[i + 1], lang: lang))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
