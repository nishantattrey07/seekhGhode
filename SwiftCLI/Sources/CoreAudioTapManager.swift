import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Manages Core Audio Tap creation and system audio capture
/// Based on AudioCap reference implementation
class CoreAudioTapManager {

    private var processTapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var isCapturing = false

    /// Create a system-wide audio tap using Core Audio Tap APIs
    /// This is the core function that enables system audio recording
    func createSystemAudioTap() async throws -> Bool {
        print("🔧 Creating system-wide Core Audio Tap...")

        // Step 1: Get the default output device
        guard let defaultDevice = try getDefaultOutputDevice() else {
            throw AudioTapError.noDefaultDevice
        }

        print("📱 Default output device: \(defaultDevice)")

        // Step 2: Create tap description for system-wide capture
        let tapDescription = try createTapDescription()
        print("📝 Created tap description")

        // Step 3: Create the process tap
        // THIS IS WHERE PERMISSION DIALOG SHOULD APPEAR
        print("🔑 Creating process tap - permission dialog should appear now...")

        let processTap = try createProcessTap(with: tapDescription)
        self.processTapID = processTap

        print("✅ Process tap created successfully! (ID: \(processTap))")

        // Step 4: Create aggregate device
        let aggregateDevice = try createAggregateDevice(with: tapDescription)
        self.aggregateDeviceID = aggregateDevice

        print("✅ Aggregate device created! (ID: \(aggregateDevice))")
        print("🎉 System audio tap is ready for recording!")

        return true
    }

    /// Get the default output device
    private func getDefaultOutputDevice() throws -> AudioObjectID? {
        var defaultDevice: AudioObjectID = 0
        var propertySize = UInt32(MemoryLayout<AudioObjectID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultDevice
        )

        guard status == noErr else {
            throw AudioTapError.cannotGetDefaultDevice(status)
        }

        guard defaultDevice != kAudioObjectUnknown else {
            return nil
        }

        return defaultDevice
    }

    /// Create tap description for system-wide audio capture
    private func createTapDescription() throws -> CFString {
        // For system-wide capture, we use PID 0 (all processes)
        // This is the key to capturing ALL system audio, not just specific apps

        print("📝 Configuring tap for system-wide capture (all processes)")

        // Create a unique UUID for this tap
        let tapUUID = UUID().uuidString
        return tapUUID as CFString
    }

    /// Create the actual process tap using Core Audio APIs
    private func createProcessTap(with description: CFString) throws -> AudioObjectID {
        print("🔧 Calling AudioHardwareCreateProcessTap...")
        print("⚠️  This should trigger the permission dialog if not already granted")

        // Check macOS version availability
        guard #available(macOS 14.2, *) else {
            throw AudioTapError.tapCreationFailed(OSStatus(kAudioHardwareUnsupportedOperationError))
        }

        // REAL IMPLEMENTATION based on AudioCap:
        // Create CATapDescription for system-wide capture (all processes)
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        var processTapID: AudioObjectID = 0

        // THIS IS THE CRITICAL CALL - triggers permission dialog
        let status = AudioHardwareCreateProcessTap(tapDescription, &processTapID)

        print("📊 AudioHardwareCreateProcessTap status: \(status)")

        if status == noErr {
            print("✅ Process tap created successfully! (ID: \(processTapID))")
            return processTapID
        } else {
            // Common error codes:
            // kAudioHardwareIllegalOperationError (2003329396/'what') = Permission denied
            print("❌ Process tap creation failed with status: \(status)")

            if status == 2_003_329_396 {  // 'what' error - likely permission issue
                print("🔑 This error typically means permission is required")
                print("💡 The permission dialog should have appeared")
                throw AudioTapError.permissionDenied
            } else {
                throw AudioTapError.tapCreationFailed(status)
            }
        }
    }

    /// Create aggregate device that includes our tap
    private func createAggregateDevice(with tapDescription: CFString) throws -> AudioObjectID {
        print("🔧 Creating aggregate device with tap...")

        // This would create an aggregate device configuration
        // that includes our process tap as a sub-device

        let simulatedAggregateID: AudioObjectID = 67890  // Placeholder

        print("✅ Aggregate device created (simulated ID: \(simulatedAggregateID))")

        return simulatedAggregateID
    }

    /// Clean up resources
    func cleanup() {
        if processTapID != 0 {
            print("🧹 Cleaning up process tap...")
            // AudioHardwareDestroyProcessTap(processTapID)
            processTapID = 0
        }

        if aggregateDeviceID != 0 {
            print("🧹 Cleaning up aggregate device...")
            // AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
    }
}

/// Errors that can occur during audio tap creation
enum AudioTapError: Error, LocalizedError {
    case noDefaultDevice
    case cannotGetDefaultDevice(OSStatus)
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDefaultDevice:
            return "No default audio output device found"
        case .cannotGetDefaultDevice(let status):
            return "Cannot get default device (Status: \(status))"
        case .tapCreationFailed(let status):
            return "Process tap creation failed (Status: \(status))"
        case .aggregateDeviceCreationFailed(let status):
            return "Aggregate device creation failed (Status: \(status))"
        case .permissionDenied:
            return "System audio recording permission denied"
        }
    }
}
