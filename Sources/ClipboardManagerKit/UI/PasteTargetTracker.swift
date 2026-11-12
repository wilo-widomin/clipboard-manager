//
//  PasteTargetTracker.swift
//  ClipboardManagerKit
//
//  Works out which app a picked item should be pasted into.
//
//  Every host has the same problem: showing the popover has to activate our own
//  app (otherwise its controls don't respond to clicks), which steals focus from
//  whatever the user was working in. So the target has to be resolved *before*
//  that, and it has to survive the user having wandered across displays and
//  Spaces since the last time they typed anything.
//

import AppKit
import ApplicationServices

/// Resolves the application to paste into, and keeps the history needed to do so.
///
/// Create one per host and keep it alive: it starts observing app activations on
/// init and the history it builds is the last-resort fallback.
@MainActor
public final class PasteTargetTracker {

    /// Rolling history of the last few non-self app activations, newest last.
    private var history: [NSRunningApplication] = []

    /// How many activations to remember. Enough to survive a couple of detours
    /// (Finder, a notification) without growing unbounded.
    private static let historyLimit = 8

    public init() {
        observeActivations()
    }

    /// The app to paste into, best guess first.
    ///
    /// Call this *before* the host activates itself to show its popover.
    public func resolve() -> NSRunningApplication? {
        Self.focusedApplication() ?? frontmostApplication() ?? lastActivated()
    }

    // MARK: - Strategies

    /// The app that actually owns keyboard focus, via the Accessibility API.
    ///
    /// This is the one that gets the paste right when the user clicks the menu
    /// bar icon on a display or Space with no windows on it: there, the
    /// *frontmost* app is the Finder (the desktop), and pasting would activate
    /// the Finder and drop the text on the floor. The focused application is
    /// still whatever the user was last typing in.
    ///
    /// No new permission is involved: posting the synthetic ⌘V already requires
    /// this process to be trusted for Accessibility, so when the paste can work
    /// at all, this query works too. Returns nil when untrusted, and the caller
    /// falls back.
    private static func focusedApplication() -> NSRunningApplication? {
        guard AXIsProcessTrusted() else { return nil }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        guard result == .success,
              let element = value,
              CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element as! AXUIElement, &pid) == .success,
              pid != ProcessInfo.processInfo.processIdentifier
        else { return nil }

        return NSRunningApplication(processIdentifier: pid)
    }

    /// Whatever is in front right now, as long as it isn't us.
    private func frontmostApplication() -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != Self.selfPID
        else { return nil }
        return front
    }

    /// The most recent app we saw activate that is still running.
    private func lastActivated() -> NSRunningApplication? {
        history.last { !$0.isTerminated && $0.processIdentifier != Self.selfPID }
    }

    // MARK: - History

    private static var selfPID: pid_t {
        NSRunningApplication.current.processIdentifier
    }

    private func observeActivations() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != Self.selfPID
            else { return }
            MainActor.assumeIsolated {
                self?.record(app)
            }
        }
    }

    private func record(_ app: NSRunningApplication) {
        history.append(app)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }
}
