import Cocoa
import SwiftUI
import LocalAuthentication

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Require authentication before setting up the app
        authenticateUser { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    self?.setupMenuBar()
                } else {
                    // Authentication failed, exit the app
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
    
    private func authenticateUser(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        // Use deviceOwnerAuthentication which allows both biometrics and password fallback
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Authenticate to access your clipboard manager"
            
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authenticationError in
                completion(success)
            }
        } else {
            // No authentication methods available
            completion(false)
        }
    }
    
    private func setupMenuBar() {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
            button.action = #selector(togglePopover(_:))
        }
        
        popover.contentViewController = NSHostingController(rootView: MenuListView(closePopover: {
            self.popover.performClose(nil)
        }))
        popover.behavior = .transient
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.becomeKey()
            }
        }
    }
}
