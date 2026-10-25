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

/// Carbon-registered global shortcuts (⌃Z for HUD palette, ⌃X for mouse radial wheel, with ⌘⇧V/⌘⌥V fallbacks).
final class GlobalHotKey {
    private static let signature = OSType(0x434C4755) // "CLGU"
    private static let standardHotKeyID = UInt32(1)
    private static let radialHotKeyID = UInt32(2)
    private static let standardFallbackHotKeyID = UInt32(3)
    private static let radialFallbackHotKeyID = UInt32(4)

    private let standardAction: () -> Void
    private let radialAction: () -> Void
    private var eventHandler: EventHandlerRef?
    private var standardHotKey: EventHotKeyRef?
    private var radialHotKey: EventHotKeyRef?
    private var standardFallbackHotKey: EventHotKeyRef?
    private var radialFallbackHotKey: EventHotKeyRef?

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

        // 1. ⌃Z (Control + Z) -> Standard HUD Palette
        let standardID = EventHotKeyID(
            signature: Self.signature,
            id: Self.standardHotKeyID
        )
        let standardStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Z),
            UInt32(controlKey),
            standardID,
            GetApplicationEventTarget(),
            0,
            &standardHotKey
        )

        guard standardStatus == noErr, standardHotKey != nil else {
            invalidate()
            throw GlobalHotKeyError.registrationFailed(standardStatus)
        }

        // 2. ⌃X (Control + X) -> Radial Wheel around mouse cursor
        let radialID = EventHotKeyID(
            signature: Self.signature,
            id: Self.radialHotKeyID
        )
        _ = RegisterEventHotKey(
            UInt32(kVK_ANSI_X),
            UInt32(controlKey),
            radialID,
            GetApplicationEventTarget(),
            0,
            &radialHotKey
        )

        // 3. Fallback: ⌘⇧V (Command + Shift + V)
        let fallbackStandardID = EventHotKeyID(
            signature: Self.signature,
            id: Self.standardFallbackHotKeyID
        )
        _ = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            fallbackStandardID,
            GetApplicationEventTarget(),
            0,
            &standardFallbackHotKey
        )

        // 4. Fallback: ⌘⌥V (Command + Option + V)
        let fallbackRadialID = EventHotKeyID(
            signature: Self.signature,
            id: Self.radialFallbackHotKeyID
        )
        _ = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | optionKey),
            fallbackRadialID,
            GetApplicationEventTarget(),
            0,
            &radialFallbackHotKey
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
        if let standardFallbackHotKey {
            UnregisterEventHotKey(standardFallbackHotKey)
            self.standardFallbackHotKey = nil
        }
        if let radialFallbackHotKey {
            UnregisterEventHotKey(radialFallbackHotKey)
            self.radialFallbackHotKey = nil
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

        if identifier.id == Self.radialHotKeyID || identifier.id == Self.radialFallbackHotKeyID {
            radialAction()
            return noErr
        } else if identifier.id == Self.standardHotKeyID || identifier.id == Self.standardFallbackHotKeyID {
            standardAction()
            return noErr
        }

        return OSStatus(eventNotHandledErr)
    }

        return OSStatus(eventNotHandledErr)
    }

    deinit {
        invalidate()
    }
}
