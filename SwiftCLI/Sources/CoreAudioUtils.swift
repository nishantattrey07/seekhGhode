import Foundation
import AudioToolbox
import AppKit

// MARK: - Constants

extension AudioObjectID {
    /// Convenience for `kAudioObjectSystemObject`.
    static let system = AudioObjectID(kAudioObjectSystemObject)
    /// Convenience for `kAudioObjectUnknown`.
    static let unknown = kAudioObjectUnknown

    /// `true` if this object has the value of `kAudioObjectUnknown`.
    var isUnknown: Bool { self == .unknown }

    /// `false` if this object has the value of `kAudioObjectUnknown`.
    var isValid: Bool { !isUnknown }
}

// MARK: - Concrete Property Helpers

extension AudioObjectID {
    /// Reads the value for `kAudioHardwarePropertyDefaultSystemOutputDevice`.
    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioDeviceID.system.readDefaultSystemOutputDevice()
    }

    static func readProcessList() throws -> [AudioObjectID] {
        try AudioObjectID.system.readProcessList()
    }

    /// Reads `kAudioHardwarePropertyTranslatePIDToProcessObject` for the specific pid.
    static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try AudioDeviceID.system.translatePIDToProcessObjectID(pid: pid)
    }

    /// Reads `kAudioHardwarePropertyProcessObjectList`.
    func readProcessList() throws -> [AudioObjectID] {
        try requireSystemObject()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0

        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)

        guard err == noErr else { throw CoreAudioError.audioPropertyError("Error reading data size for \(address): \(err)") }

        var value = [AudioObjectID](repeating: .unknown, count: Int(dataSize) / MemoryLayout<AudioObjectID>.size)

        err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)

        guard err == noErr else { throw CoreAudioError.audioPropertyError("Error reading array for \(address): \(err)") }

        return value
    }

    /// Reads `kAudioHardwarePropertyTranslatePIDToProcessObject` for the specific pid, should only be called on the system object.
    func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try requireSystemObject()

        let processObject = try read(
            kAudioHardwarePropertyTranslatePIDToProcessObject,
            defaultValue: AudioObjectID.unknown,
            qualifier: UInt32(pid)
        )

        guard processObject.isValid else {
            throw CoreAudioError.invalidProcessIdentifier(pid)
        }

        return processObject
    }

    func readProcessBundleID() -> String? {
        if let result = try? readString(kAudioProcessPropertyBundleID) {
            result.isEmpty ? nil : result
        } else {
            nil
        }
    }

    func readProcessIsRunning() -> Bool {
        (try? readBool(kAudioProcessPropertyIsRunning)) ?? false
    }

    func readProcessPID() throws -> pid_t {
        try read(kAudioProcessPropertyPID, defaultValue: pid_t(0))
    }

    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func readDeviceUID() throws -> String {
        try readString(kAudioDevicePropertyDeviceUID)
    }

    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }
}

// MARK: - Generic Property Reading

extension AudioObjectID {
    
    func requireSystemObject() throws {
        guard self == .system else {
            throw CoreAudioError.systemObjectRequired
        }
    }

    func read<T>(_ selector: AudioObjectPropertySelector, defaultValue: T, qualifier: UInt32 = 0) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value = defaultValue
        var dataSize = UInt32(MemoryLayout<T>.size)
        var qualifierValue = qualifier

        let err = withUnsafeMutablePointer(to: &value) { valuePtr in
            AudioObjectGetPropertyData(self, &address, UInt32(MemoryLayout<UInt32>.size), &qualifierValue, &dataSize, valuePtr)
        }

        guard err == noErr else { throw CoreAudioError.audioPropertyError("Error reading property \(selector): \(err)") }

        return value
    }

    func readString(_ selector: AudioObjectPropertySelector, qualifier: UInt32 = 0) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var qualifierValue = qualifier

        var err = AudioObjectGetPropertyDataSize(self, &address, UInt32(MemoryLayout<UInt32>.size), &qualifierValue, &dataSize)

        guard err == noErr else { throw CoreAudioError.audioPropertyError("Error reading data size for \(address): \(err)") }

        var value = [CChar](repeating: 0, count: Int(dataSize))

        err = AudioObjectGetPropertyData(self, &address, UInt32(MemoryLayout<UInt32>.size), &qualifierValue, &dataSize, &value)

        guard err == noErr else { throw CoreAudioError.audioPropertyError("Error reading string for \(address): \(err)") }

        return String(cString: value)
    }

    func readBool(_ selector: AudioObjectPropertySelector, qualifier: UInt32 = 0) throws -> Bool {
        let value: UInt32 = try read(selector, defaultValue: 0, qualifier: qualifier)
        return value != 0
    }
}

// MARK: - Error Handling

enum CoreAudioError: Error, LocalizedError {
    case audioPropertyError(String)
    case invalidProcessIdentifier(pid_t)
    case systemObjectRequired
    
    var errorDescription: String? {
        switch self {
        case .audioPropertyError(let message):
            return message
        case .invalidProcessIdentifier(let pid):
            return "Invalid process identifier: \(pid)"
        case .systemObjectRequired:
            return "This method can only be called on the system object"
        }
    }
}
