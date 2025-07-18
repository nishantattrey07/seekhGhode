import AVFoundation
import CoreAudio
import Foundation
import OSLog

/// Main entry point for macOS System Audio Recording CLI
/// This CLI uses Core Audio Tap APIs (AudioCap implementation) to capture system audio only
/// without triggering screen recording permissions.

@available(macOS 14.2, *)
func main() async {
    print("🎯 macOS System Audio-Only Recorder (AudioCap Based)")
    print("📋 Using Core Audio Tap APIs (macOS 14.2+)")
    print("🔑 Requesting: System Audio Recording Only")
    print("❌ NOT requesting: Screen Recording or Microphone")
    print()

    // Parse command line arguments
    let arguments = CommandLine.arguments

    if arguments.count < 2 {
        printUsage()
        return
    }

    let command = arguments[1].lowercased()

    switch command {
    case "list":
        await listProcesses()
    case "test-permission":
        await testPermissionFlow()
    case "start":
        if arguments.count > 2 {
            await startRecording(targetProcessName: arguments[2])
        } else {
            await startRecording()
        }
    case "record-safari":
        await recordSafariAudio()
    case "help", "--help", "-h":
        printUsage()
    default:
        print("❌ Unknown command: \(command)")
        printUsage()
    }
}

func printUsage() {
    print("Usage:")
    print("  AudioRecorderCLI list              # List available audio processes")
    print("  AudioRecorderCLI test-permission   # Test permission dialog")
    print("  AudioRecorderCLI start [process]   # Start system audio recording")
    print("  AudioRecorderCLI record-safari     # Record from Safari (YouTube audio)")
    print("  AudioRecorderCLI help              # Show this help")
    print()
    print("🎯 Goal: Verify 'System Audio Recording Only' permission using AudioCap implementation")
}

// Run the main function
if #available(macOS 14.2, *) {
    await main()
} else {
    print("❌ This app requires macOS 14.2 or later for Core Audio Tap APIs")
    exit(1)
}

/// List all available audio processes
@available(macOS 14.2, *)
func listProcesses() async {
    print("📱 Discovering Audio Processes...")
    print()

    let controller = AudioProcessController()
    controller.listProcesses()
}

/// Test the permission flow to verify correct dialog appears
@available(macOS 14.2, *)
func testPermissionFlow() async {
    print("🧪 Testing Permission Flow (AudioCap Implementation)...")
    print("📱 Expected: 'System Audio Recording Only' dialog")
    print("⚠️  Should NOT see 'Screen Recording' permission")
    print()

    let controller = AudioProcessController()
    let processes = controller.getAvailableProcesses()

    guard let testProcess = processes.first else {
        print("❌ No audio processes found to test with")
        return
    }

    print("🔍 Testing with process: \(testProcess.name)")
    print("⏳ Creating process tap - permission dialog should appear...")

    let tap = ProcessTap(process: testProcess)
    tap.activate()

    if let error = tap.errorMessage {
        print("❌ Permission test failed: \(error)")
        print("💡 Please go to System Settings > Privacy & Security > Screen & System Audio Recording")
        print("💡 Enable permission for this app")
    } else {
        print("✅ Permission granted! Process tap created successfully!")
        print("🎉 CHECKPOINT 1 PASSED: Can create tap without screen recording permission")
        tap.invalidate()
    }
}

/// Start actual recording
@available(macOS 14.2, *)
func startRecording() async {
    await startRecording(targetProcessName: nil)
}

/// Record from Safari specifically (for YouTube audio)
@available(macOS 14.2, *)
func recordSafariAudio() async {
    print("🎬 Recording Safari Audio (YouTube/Web Audio)...")
    await startRecording(targetProcessName: "Safari")
}

/// Start actual recording with optional process targeting
@available(macOS 14.2, *)
func startRecording(targetProcessName: String? = nil) async {
    print("🎬 Starting system audio recording (AudioCap Implementation)...")

    let controller = AudioProcessController()
    let processes = controller.getAvailableProcesses()

    var targetProcess: AudioProcess?

    if let targetName = targetProcessName {
        // Find the specified process
        targetProcess = processes.first { 
            $0.name.lowercased().contains(targetName.lowercased()) && $0.audioActive 
        }
        
        if targetProcess == nil {
            print("❌ No active audio process found matching '\(targetName)'")
            print("💡 Try running 'AudioRecorderCLI list' to see available processes")
            return
        }
    } else {
        // Find any active process, prefer Safari Graphics and Media for web audio
        targetProcess = processes.first { 
            $0.name.contains("Safari Graphics and Media") && $0.audioActive 
        } ?? processes.first { $0.audioActive }
    }

    guard let process = targetProcess else {
        print("❌ No active audio processes found")
        print("💡 Make sure some app is playing audio (e.g., YouTube in Safari/Chrome)")
        return
    }

    print("🎯 Recording from: \(process.name) (🎵 ACTIVE)")

    // Default output path
    let outputPath =
        "\(NSHomeDirectory())/Desktop/system_audio_\(Int(Date().timeIntervalSince1970)).wav"
    let outputURL = URL(fileURLWithPath: outputPath)
    
    print("📁 Output: \(outputPath)")
    print("⏸️  Press Ctrl+C to stop")
    print()

    let tap = ProcessTap(process: process)
    let recorder = ProcessTapRecorder(fileURL: outputURL, tap: tap)

    do {
        // Start recording
        try recorder.start()
        print("🎤 Recording... Press Ctrl+C to stop")

        // Set up signal handling for graceful shutdown
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)

        signalSource.setEventHandler {
            print("\n⏹️ Stopping recording...")
            recorder.stop()
            print("✅ Recording saved to: \(outputPath)")
            exit(0)
        }
        signalSource.resume()

        // Keep the program running
        while recorder.isRecording {
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
        }
    } catch {
        print("❌ Failed to start recording: \(error)")
        return
    }
}
