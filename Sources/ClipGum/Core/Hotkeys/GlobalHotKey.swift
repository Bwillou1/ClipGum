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
            return "Global shortcuts could not be registered (status \(status)). Another app may own the shortcut."
        }
    }
}

/// Carbon-registered global shortcuts (⌘⇧V for HUD palette, ⌘⌥V for mouse radial wheel).
final class GlobalHotKey {
    private static let signature = OSType(0x434C4755) // "CLGU"
    private static let standardHotKeyID = UInt32(1)
    private static let radialHotKeyID = UInt32(2)

    private let standardAction: () -> Void
    private let radialAction: () -> Void
    private var eventHandler: EventHandlerRef?
    private var standardHotKey: EventHotKeyRef?
    private var radialHotKey: EventHotKeyRef?

    init(
        standardAction: @escaping () -> Void,
        radialAction: @escaping () -> Void = {}
    ) {
        self.standardAction = standardAction
        self.radialAction = radialAction
    }

    func registerShortcuts() throws {
        guard standardHotKey == nil else {
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

        // 1. ⌘⇧V (Command + Shift + V) -> Standard HUD
        let standardID = EventHotKeyID(
            signature: Self.signature,
            id: Self.standardHotKeyID
        )
        let standardStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            standardID,
            GetApplicationEventTarget(),
            0,
            &standardHotKey
        )

        guard standardStatus == noErr, standardHotKey != nil else {
            invalidate()
            throw GlobalHotKeyError.registrationFailed(standardStatus)
        }

        // 2. ⌘⌥V (Command + Option + V) -> Radial Wheel around mouse
        let radialID = EventHotKeyID(
            signature: Self.signature,
            id: Self.radialHotKeyID
        )
        _ = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | optionKey),
            radialID,
            GetApplicationEventTarget(),
            0,
            &radialHotKey
        )
    }

    func registerCommandShiftV() throws {
        try registerShortcuts()
    }

    func invalidate() {
        if let standardHotKey {
            UnregisterEventHotKey(standardHotKey)
            self.standardHotKey = nil
        }
        if let radialHotKey {
            UnregisterEventHotKey(radialHotKey)
            self.radialHotKey = nil
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
        guard identifier.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }

        if identifier.id == Self.radialHotKeyID {
            radialAction()
            return noErr
        } else if identifier.id == Self.standardHotKeyID {
            standardAction()
            return noErr
        }

        return OSStatus(eventNotHandledErr)
    }

    deinit {
        invalidate()
    }
}
