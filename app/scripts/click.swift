// Posts a synthetic mouse click at screen coordinates.
//
//     swiftc -O click.swift -o click
//     ./click 858 296            # left click
//     ./click 858 296 right      # context menu
//     ./click 858 296 double     # open / edit
//
// AppleScript's `click at {x, y}` and `set selected of row N` both silently do
// nothing to a SwiftUI List, which is why this exists: a CGEvent posted to the
// HID event tap is indistinguishable from the real mouse. Coordinates are in
// screen points, origin top-left, the same frame `screencapture -R` uses.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: click X Y [right|double]\n".utf8))
    exit(2)
}
let mode = args.count > 3 ? args[3] : "left"
let point = CGPoint(x: x, y: y)

func post(_ type: CGEventType, _ button: CGMouseButton, clicks: Int64 = 1) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: button) else { return }
    event.setIntegerValueField(.mouseEventClickState, value: clicks)
    event.post(tap: .cghidEventTap)
}

CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
        mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(60_000)

switch mode {
case "right":
    post(.rightMouseDown, .right); usleep(40_000); post(.rightMouseUp, .right)
case "double":
    post(.leftMouseDown, .left); usleep(30_000); post(.leftMouseUp, .left); usleep(140_000)
    post(.leftMouseDown, .left, clicks: 2); usleep(30_000); post(.leftMouseUp, .left, clicks: 2)
default:
    post(.leftMouseDown, .left); usleep(40_000); post(.leftMouseUp, .left)
}
