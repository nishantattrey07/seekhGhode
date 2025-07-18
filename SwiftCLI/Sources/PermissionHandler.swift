import AVFoundation
import CoreAudio
import Foundation

/// Handles macOS system audio recording permissions
/// Uses NSAudioCaptureUsageDescription to trigger "System Audio Recording Only" dialog
class PermissionHandler {

    /// Check if app currently has system audio recording permission
    /// This is a basic implementation - proper TCC checking requires private APIs
    func checkAudioCapturePermission() async -> Bool {
        print("🔍 Checking audio capture permission status...")

        // For now, we'll attempt to create a basic audio tap to test permission
        // If this succeeds, we have permission. If it fails, we likely don't.
        return await testBasicAudioAccess()
    }

    /// Request system audio recording permission
    /// This will trigger the macOS permission dialog with NSAudioCaptureUsageDescription
    func requestAudioCapturePermission() async -> Bool {
        print("🔑 Requesting system audio recording permission...")
        print("📱 This should show 'System Audio Recording Only' dialog")

        // Attempt to create a Core Audio tap, which will trigger permission request
        return await attemptCoreAudioTapCreation()
    }

    /// Test basic audio access without full tap creation
    private func testBasicAudioAccess() async -> Bool {
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

        if status == noErr && defaultDevice != kAudioObjectUnknown {
            print("✅ Can access default audio device (ID: \(defaultDevice))")
            return true
        } else {
            print("❌ Cannot access default audio device (Status: \(status))")
            return false
        }
    }

    /// Attempt to create a Core Audio tap to test/request permission
    private func attemptCoreAudioTapCreation() async -> Bool {
        print("🔧 Attempting Core Audio tap creation to trigger permission...")

        // Check macOS version availability
        guard #available(macOS 14.2, *) else {
            print("❌ Core Audio Tap APIs require macOS 14.2+")
            return false
        }

        // Create a minimal tap description that should trigger permission
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        var processTapID: AudioObjectID = 0

        print("⏳ Creating process tap - permission dialog should appear...")
        let status = AudioHardwareCreateProcessTap(tapDescription, &processTapID)

        print("📊 AudioHardwareCreateProcessTap result: \(status)")

        if status == noErr {
            print("✅ Process tap created - permission granted!")
            // Clean up immediately
            AudioHardwareDestroyProcessTap(processTapID)
            return true
        } else if status == 2_003_329_396 {  // 'what' error - permission denied
            print("❌ Permission denied (need to grant in System Preferences)")
            return false
        } else {
            print("❌ Tap creation failed with status: \(status)")
            return false
        }
    }
}
