import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case handlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .handlerInstallationFailed(let status):
            return "The Carbon event handler could not be installed (status \(status))."
        case .registrationFailed(let status):
            return "⌘⇧V could not be registered (status \(status)). Another app may own the shortcut."
        }
    }
}

/// A single Carbon-registered global shortcut.
///
/// Carbon delivers only the registered hotkey, unlike a global NSEvent keyboard
/// monitor which observes every key. No Accessibility permission is needed to
/// register this shortcut.
final class GlobalHotKey {
    private static let signature = OSType(0x434C4755) // "CLGU"
    private static let hotKeyIdentifier = UInt32(1)

    private let action: () -> Void
    private var eventHandler: EventHandlerRef?
    private var eventHotKey: EventHotKeyRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func registerCommandShiftV() throws {
        guard eventHotKey == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return hotKey.handleEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard handlerStatus == noErr, let handler else {
            throw GlobalHotKeyError.handlerInstallationFailed(handlerStatus)
        }
        eventHandler = handler

        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.hotKeyIdentifier
        )
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )

        guard registrationStatus == noErr, eventHotKey != nil else {
            if let eventHotKey {
                UnregisterEventHotKey(eventHotKey)
                self.eventHotKey = nil
            }
            RemoveEventHandler(handler)
            eventHandler = nil
            throw GlobalHotKeyError.registrationFailed(registrationStatus)
        }
    }

    func invalidate() {
        if let eventHotKey {
            UnregisterEventHotKey(eventHotKey)
            self.eventHotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func handleEvent(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr else {
            return status
        }
        guard
            identifier.signature == Self.signature,
            identifier.id == Self.hotKeyIdentifier
        else {
            return OSStatus(eventNotHandledErr)
        }

        // Carbon invokes this handler on the app's event loop.
        action()
        return noErr
    }

    deinit {
        invalidate()
    }
}
