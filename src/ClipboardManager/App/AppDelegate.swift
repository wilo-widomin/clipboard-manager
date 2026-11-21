//
//  AppDelegate.swift
//  ClipboardManager
//
//  Application entry point. LSUIElement = YES so the app runs as an agent
//  (no Dock icon, no menu bar). Loads persisted state, starts the clipboard
//  monitor, and installs the status item.
//

import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Programmatic entry point. We drive the `NSApplication` lifecycle ourselves
    /// (rather than relying on `NSApplicationMain` / a storyboard) because this is
    /// a menu-bar agent with no Dock icon and no main window. `application.run()`
    /// starts the AppKit run loop that keeps the process alive and delivers
    /// `applicationDidFinishLaunching` — without it the process exits immediately
    /// and the status item is never installed.
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        // Reinforce LSUIElement=YES at runtime: run as an accessory (menu-bar)
        // app with no Dock presence and no application menu in the menu bar.
        application.setActivationPolicy(.accessory)

        // Sin menú principal no hay atajos de edición en los campos de texto.
        EditMenu.install(on: application)

        application.run()
    }

    private var store: ClipboardStore?
    private var monitor: ClipboardMonitor?
    private var statusItemController: StatusItemController?
    private var tickTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let persistence = JSONPersistenceService()
        let store = ClipboardStore(persistence: persistence)
        self.store = store

        // Install the status item.
        let controller = StatusItemController(store: store)
        self.statusItemController = controller
        self.monitor = ClipboardMonitor(store: store)

        // Load persisted state. Hasta que no se ha leído (y descifrado) lo que
        // hay en disco no se empieza a capturar: si los datos no se pueden
        // abrir, la app avisa y se cierra sin escribir nada.
        Task {
            await store.load()
            if let error = persistence.blockingError {
                self.stopBecauseDataIsUnreadable(error)
                return
            }
            self.startMonitoring()
        }
    }

    /// Start the 1 Hz tick for clipboard monitoring. The popover UI is SwiftUI
    /// bound to the store's @Published state, so it refreshes automatically
    /// when the monitor adds items — no manual menu rebuild needed.
    private func startMonitoring() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.monitor?.tick()
            }
        }
    }

    /// Los archivos existen pero no se pueden leer (sin llave en el Llavero,
    /// aviso del Llavero rechazado, descifrado que falla, JSON roto). La
    /// persistencia ya ha bloqueado toda escritura; aquí se explica y se sale,
    /// para que Willy no trabaje con un historial vacío creyendo que lo ha
    /// perdido.
    private func stopBecauseDataIsUnreadable(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "No se puede abrir el historial"
        alert.informativeText = """
            Clipboard Manager no ha podido leer sus datos y se va a cerrar sin \
            tocarlos, para no perder nada.

            \(error.localizedDescription)

            Los archivos siguen en ~/Library/Application Support/ClipboardManager. \
            Si el Llavero ha pedido permiso y lo has rechazado, vuelve a abrir la \
            app y pulsa «Permitir siempre».
            """
        alert.addButton(withTitle: "Salir")
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        tickTimer?.invalidate()
    }

    /// Opt in to secure state restoration (silences the macOS 14+ warning).
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}