import AppKit
import SwiftUI
import Testing
@testable import Ovation

// TEMPORARY PROBE for ovation#647, removed before the pull request is ready: repeats the floating review
// sheet capture so an intermittent NaN warning has many chances to show.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NaNProbeTests {
    @Test func probeFloating() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nan-probe")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for round in 0..<16 {
            for size in [CGSize(width: OvationWindow.minimumWidth, height: OvationWindow.minimumHeight),
                         CGSize(width: 1064, height: 900)] {
                for scheme in [ColorScheme.light, .dark] {
                    let presenter = try ReviewSampleWorld.presenter(for: .ordinary)
                    let page = InvoicePage()
                    try presenter.show(on: page)
                    let floating = FloatingSheet(below: ShellView.titleBarHeight, dim: .deep) {
                        ReviewSheet(presenter: presenter, page: page, close: {})
                    }
                    NSLog("NANPROBE begin round %d %dx%d %@", round, Int(size.width), Int(size.height),
                          scheme == .light ? "light" : "dark")
                    try OffscreenShot.capture(floating, size: size, scheme: scheme,
                                              to: directory.appending(path: "p.png"))
                    NSLog("NANPROBE end")
                }
            }
        }
    }

    @Test func probeUnfloated() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "nan-probe")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for round in 0..<12 {
            for size in [CGSize(width: OvationWindow.minimumWidth, height: OvationWindow.minimumHeight),
                         CGSize(width: 1064, height: 900)] {
                let presenter = try ReviewSampleWorld.presenter(for: .ordinary)
                let page = InvoicePage()
                try presenter.show(on: page)
                let sheet = ReviewSheet(presenter: presenter, page: page, close: {})
                NSLog("NANPROBE unfloated begin round %d %dx%d", round, Int(size.width), Int(size.height))
                try OffscreenShot.capture(sheet, size: size, scheme: .light,
                                          to: directory.appending(path: "q.png"))
                NSLog("NANPROBE end")
            }
        }
    }
}

