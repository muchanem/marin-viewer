// Drive and capture a running Marin Viewer window for UI review.
//
//   swift tools/viewer-ui.swift launch [--viewer-pr N]   start a new instance on the Retina screen, print its pid
//   swift tools/viewer-ui.swift place <pid> [W H]         move the window to the Retina display (default 1440x900)
//   swift tools/viewer-ui.swift dump <pid> [depth]        print the accessibility tree of the front window
//   swift tools/viewer-ui.swift menubar <pid>             print the menu bar titles and the app menu's items
//   swift tools/viewer-ui.swift press <pid> <text>        press the first element whose title or description contains text
//   swift tools/viewer-ui.swift keys <pid> <key> [cmd,shift,option,control]
//   swift tools/viewer-ui.swift capture <pid> <out.png>   capture the window, active, without shadow; refuses
//                                                          a window that is not wholly on the Retina screen
//   swift tools/viewer-ui.swift snap <pid> <out.png> [pad] capture the screen area of the window plus `pad`
//                                                          points, so sheets, menus and popovers show too
//   swift tools/viewer-ui.swift click <pid> X Y [right|double|cmd]
//                                                          click at window point X,Y (top-left origin)
//   swift tools/viewer-ui.swift scroll <pid> X Y DY        scroll DY lines (negative scrolls down) at X,Y
//   swift tools/viewer-ui.swift type <pid> <text>          type text into the focused control
//   swift tools/viewer-ui.swift menu <pid> <title>         choose a menu bar item by its exact title
//   swift tools/viewer-ui.swift quit <pid>                 quit the instance politely (runs its close path)
//
// Needs Screen Recording and Accessibility for the terminal. All captures and interactive checks
// happen on the built-in Retina screen: the external ultrawide is 1x, which halves the detail, and
// Mark's other work is open there. Activate before capturing, or the window draws in its inactive
// style (grey traffic lights and selection).

import AppKit
import ApplicationServices

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func label(_ e: AXUIElement) -> String {
    for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
        if let s = attr(e, name) as? String, !s.isEmpty { return s }
    }
    return ""
}

func frontWindow(_ pid: pid_t) -> AXUIElement {
    guard AXIsProcessTrusted() else { fail("Accessibility is not granted to this terminal") }
    let app = AXUIElementCreateApplication(pid)
    guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement], let w = windows.first else {
        fail("process \(pid) has no accessible window")
    }
    return w
}

func activate(_ pid: pid_t) {
    NSRunningApplication(processIdentifier: pid)?.activate()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
}

func retinaScreen() -> NSScreen {
    guard let s = NSScreen.screens.first(where: { $0.backingScaleFactor > 1 }) else { fail("no Retina screen") }
    return s
}

/// A screen's frame in window-server coordinates (top-left origin on the primary screen).
func serverFrame(_ screen: NSScreen) -> CGRect {
    let primaryHeight = NSScreen.screens[0].frame.height
    let f = screen.frame
    return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
}

func place(_ pid: pid_t, width: Double = 1440, height: Double = 900) -> String {
    let retina = retinaScreen()
    let visible = retina.visibleFrame
    let primaryHeight = NSScreen.screens[0].frame.height
    var origin = CGPoint(x: visible.minX + 10, y: primaryHeight - visible.maxY + 4)
    var size = CGSize(width: min(width, visible.width - 20), height: min(height, visible.height - 8))
    let window = frontWindow(pid)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    activate(pid)
    return "placed at \(origin) size \(size) on \(retina.localizedName)"
}

func mainWindow(_ pid: pid_t) -> (number: Int, bounds: CGRect) {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let mine = list.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
    }
    // The main window is the largest; the narrow strips are toolbar and menu helpers.
    let best = mine.max { a, b in
        let area = { (w: [String: Any]) -> Double in
            let r = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return (r["Width"] ?? 0) * (r["Height"] ?? 0)
        }
        return area(a) < area(b)
    }
    guard let best, let n = best[kCGWindowNumber as String] as? Int,
          let r = best[kCGWindowBounds as String] as? [String: Double] else { fail("process \(pid) has no on-screen window") }
    return (n, CGRect(x: r["X"] ?? 0, y: r["Y"] ?? 0, width: r["Width"] ?? 0, height: r["Height"] ?? 0))
}

func pressable(_ e: AXUIElement) -> Bool {
    var actions: CFArray?
    guard AXUIElementCopyActionNames(e, &actions) == .success, let names = actions as? [String] else { return false }
    return names.contains(kAXPressAction as String)
}

/// The first pressable element whose label contains `text`, so static captions that repeat a
/// button's words are skipped.
func find(_ e: AXUIElement, _ text: String, _ depth: Int = 0) -> AXUIElement? {
    if pressable(e), label(e).localizedCaseInsensitiveContains(text) { return e }
    guard depth < 30, let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    for k in kids { if let hit = find(k, text, depth + 1) { return hit } }
    return nil
}

func dump(_ e: AXUIElement, _ depth: Int, _ maxDepth: Int) {
    let role = attr(e, kAXRoleAttribute) as? String ?? "?"
    let text = label(e).replacingOccurrences(of: "\n", with: " ")
    print(String(repeating: "  ", count: depth) + role + (text.isEmpty ? "" : " “\(text.prefix(60))”"))
    guard depth < maxDepth, let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return }
    for k in kids { dump(k, depth + 1, maxDepth) }
}

let args = CommandLine.arguments.dropFirst()
guard let command = args.first else { fail("usage: see the header of tools/viewer-ui.swift") }
let rest = Array(args.dropFirst())
let pid = rest.first.flatMap { pid_t($0) }

switch command {
case "launch":
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let app = root.appending(path: "build/Marin Viewer.app")
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.arguments = rest
    var launched: NSRunningApplication?
    NSWorkspace.shared.openApplication(at: app, configuration: config) { app, error in
        if let error { fail("launch failed: \(error.localizedDescription)") }
        launched = app
    }
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        if let p = launched?.processIdentifier,
           let ws = attr(AXUIElementCreateApplication(p), kAXWindowsAttribute) as? [AXUIElement], !ws.isEmpty {
            FileHandle.standardError.write(Data((place(p) + "\n").utf8))
            print(p)
            exit(0)
        }
    }
    fail("no window within 20 s")
case "place":
    guard let pid else { fail("place <pid> [W H]") }
    print(rest.count > 2 ? place(pid, width: Double(rest[1])!, height: Double(rest[2])!) : place(pid))
case "dump":
    guard let pid else { fail("dump <pid> [depth]") }
    dump(frontWindow(pid), 0, rest.count > 1 ? Int(rest[1])! : 4)
case "menubar":
    guard let pid else { fail("menubar <pid>") }
    guard AXIsProcessTrusted() else { fail("Accessibility is not granted to this terminal") }
    guard let bar = attr(AXUIElementCreateApplication(pid), kAXMenuBarAttribute),
          let menus = attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else {
        fail("process \(pid) has no accessible menu bar")
    }
    print("menu bar: " + menus.map { "“\(label($0))”" }.joined(separator: " "))
    // The app menu is the first title after the Apple menu; its items are one level down.
    if menus.count > 1, let menu = (attr(menus[1], kAXChildrenAttribute) as? [AXUIElement])?.first,
       let items = attr(menu, kAXChildrenAttribute) as? [AXUIElement] {
        for item in items where !label(item).isEmpty { print("  \(label(item))") }
    }
case "press":
    guard let pid, rest.count > 1 else { fail("press <pid> <text>") }
    activate(pid)
    guard let e = find(frontWindow(pid), rest[1]) else { fail("nothing labelled “\(rest[1])”") }
    let result = AXUIElementPerformAction(e, kAXPressAction as CFString)
    print(result == .success ? "pressed “\(label(e))”" : "press failed: \(result.rawValue)")
case "keys":
    guard let pid, rest.count > 1 else { fail("keys <pid> <key> [modifiers]") }
    activate(pid)
    var codes: [String: CGKeyCode] = ["return": 36, "escape": 53, "tab": 48, "space": 49, "down": 125, "up": 126,
                                      "left": 123, "right": 124, "period": 47, "comma": 43, "slash": 44,
                                      "leftbracket": 33, "rightbracket": 30, "delete": 51]
    let letters: [Character: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
                                           "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
                                           "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
                                           "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29]
    for (k, v) in letters { codes[String(k)] = v }
    guard let code = codes[rest[1].lowercased()] else { fail("unknown key \(rest[1]); known: \(codes.keys.sorted())") }
    var flags = CGEventFlags()
    for m in (rest.count > 2 ? rest[2] : "").split(separator: ",") {
        switch m {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "option": flags.insert(.maskAlternate)
        case "control": flags.insert(.maskControl)
        default: fail("unknown modifier \(m)")
        }
    }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = flags
        event.postToPid(pid)
    }
    print("sent \(rest[1]) \(rest.count > 2 ? rest[2] : "")")
case "capture":
    guard let pid, rest.count > 1 else { fail("capture <pid> <out.png>") }
    activate(pid)
    let window = mainWindow(pid)
    let retina = serverFrame(retinaScreen())
    guard retina.contains(window.bounds) else {
        fail("window \(window.bounds) is not wholly on the Retina screen \(retina); run `place \(pid)` first")
    }
    let task = Process()
    task.executableURL = URL(filePath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l\(window.number)", rest[1]]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0, let image = NSImage(contentsOfFile: rest[1]),
          let rep = image.representations.first else { fail("capture failed") }
    print("\(rest[1]) \(rep.pixelsWide)x\(rep.pixelsHigh)")
case "snap":
    guard let pid, rest.count > 1 else { fail("snap <pid> <out.png> [pad]") }
    activate(pid)
    let pad = rest.count > 2 ? Double(rest[2])! : 0
    let retina = serverFrame(retinaScreen())
    let area = mainWindow(pid).bounds.insetBy(dx: -pad, dy: -pad).intersection(retina)
    guard !area.isNull, retina.contains(mainWindow(pid).bounds) else { fail("window is not on the Retina screen; run `place \(pid)` first") }
    let task = Process()
    task.executableURL = URL(filePath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-R\(Int(area.minX)),\(Int(area.minY)),\(Int(area.width)),\(Int(area.height))", rest[1]]
    try task.run()
    task.waitUntilExit()
    print(task.terminationStatus == 0 ? rest[1] : "capture failed")
case "click", "scroll":
    guard let pid, rest.count > (command == "scroll" ? 3 : 2), let x = Double(rest[1]), let y = Double(rest[2]) else {
        fail("click <pid> X Y [right|double|cmd] or scroll <pid> X Y DY")
    }
    activate(pid)
    let bounds = mainWindow(pid).bounds
    let point = CGPoint(x: bounds.minX + x, y: bounds.minY + y)
    guard serverFrame(retinaScreen()).contains(point) else { fail("point \(point) is not on the Retina screen") }
    if command == "scroll" {
        let lines = Int32(rest[3])!
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)!
        move.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        for _ in 0..<abs(lines) {
            let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines > 0 ? 1 : -1, wheel2: 0, wheel3: 0)!
            e.location = point
            e.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        print("scrolled \(lines) at \(x),\(y)")
    } else {
        let style = rest.count > 3 ? rest[3] : ""
        let right = style == "right"
        let (down, up): (CGEventType, CGEventType) = right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)!
        move.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        for click in 1...(style == "double" ? 2 : 1) {
            for type in [down, up] {
                let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: right ? .right : .left)!
                e.setIntegerValueField(.mouseEventClickState, value: Int64(click))
                if style == "cmd" { e.flags = .maskCommand }
                e.post(tap: .cghidEventTap)
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
        }
        print("clicked \(style.isEmpty ? "left" : style) at \(x),\(y)")
    }
case "type":
    guard let pid, rest.count > 1 else { fail("type <pid> <text>") }
    activate(pid)
    for scalar in rest[1].utf16 {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
            var unit = scalar
            e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            e.post(tap: .cghidEventTap)  // to the active app, which `activate` made this one
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))  // filtering fields drop a burst
        }
    }
    print("typed \(rest[1].count) characters")
case "menu":
    guard let pid, rest.count > 1 else { fail("menu <pid> <item title>") }
    activate(pid)
    guard let bar = attr(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { fail("no menu bar") }
    func item(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
        let role = attr(e, kAXRoleAttribute) as? String
        if role == kAXMenuItemRole as String, label(e) == rest[1] { return e }
        guard depth < 6, let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for k in kids { if let hit = item(k, depth + 1) { return hit } }
        return nil
    }
    guard let e = item(bar as! AXUIElement, 0) else { fail("no menu item “\(rest[1])”") }
    let result = AXUIElementPerformAction(e, kAXPressAction as CFString)
    print(result == .success ? "chose “\(rest[1])”" : "menu press failed: \(result.rawValue)")
case "quit":
    guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { fail("quit <pid>") }
    print(app.terminate() ? "asked \(pid) to quit" : "quit failed")
default:
    fail("unknown command \(command)")
}
