import Foundation
import AudioToolbox
import OSLog
import AVFoundation

/// Core process tap implementation for capturing audio from specific processes
/// Adapted from AudioCap: https://github.com/insidegui/AudioCap
@available(macOS 14.2, *)
class ProcessTap {

    typealias InvalidationHandler = (ProcessTap) -> Void

    let process: AudioProcess
    let muteWhenRunning: Bool
    private let logger: Logger

    private(set) var errorMessage: String? = nil

    init(process: AudioProcess, muteWhenRunning: Bool = false) {
        self.process = process
        self.muteWhenRunning = muteWhenRunning
        self.logger = Logger(subsystem: "AudioRecorderCLI", category: "ProcessTap(\(process.name))")
    }

    /// Create a system-wide tap that captures all audio processes
    convenience init(systemWide: Bool = true) {
        // Create a dummy process for system-wide capture
        let systemProcess = AudioProcess(
            id: 0,
            kind: .process,
            name: "System-Wide Audio",
            audioActive: true,
            bundleID: nil,
            bundleURL: nil,
            objectID: .system
        )
        self.init(process: systemProcess, muteWhenRunning: false)
    }

    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID = AudioObjectID.unknown
    private var deviceProcID: AudioDeviceIOProcID?
    private(set) var tapStreamDescription: AudioStreamBasicDescription?
    private var invalidationHandler: InvalidationHandler?

    private(set) var activated = false

    /// Activate the process tap (create tap and aggregate device)
    func activate() {
        guard !activated else { return }
        activated = true

        logger.debug("Activating process tap for \(self.process.name)")

        self.errorMessage = nil

        do {
            if process.name == "System-Wide Audio" {
                try prepareSystemWide()
            } else {
                try prepare(for: process.objectID)
            }
        } catch {
            logger.error("Activation failed: \(error)")
            self.errorMessage = error.localizedDescription
        }
    }

    /// Invalidate and clean up the tap
    func invalidate() {
        guard activated else { return }
        defer { activated = false }

        logger.debug("Invalidating process tap")

        invalidationHandler?(self)
        self.invalidationHandler = nil

        if aggregateDeviceID.isValid {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr { logger.warning("Failed to stop aggregate device: \(err)") }

            if let deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if err != noErr { logger.warning("Failed to destroy device I/O proc: \(err)") }
                self.deviceProcID = nil
            }

            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err)")
            }
            aggregateDeviceID = .unknown
        }

        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                logger.warning("Failed to destroy audio tap: \(err)")
            }
            self.processTapID = .unknown
        }
    }

    /// Prepare the tap for the given process object ID
    private func prepare(for objectID: AudioObjectID) throws {
        errorMessage = nil

        // Create tap description
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [objectID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = muteWhenRunning ? .mutedWhenTapped : .unmuted
        
        var tapID: AUAudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard err == noErr else {
            let errorMsg = "Process tap creation failed with error \(err)"
            logger.error("\(errorMsg)")
            throw CoreAudioError.audioPropertyError(errorMsg)
        }

        logger.debug("Created process tap #\(tapID)")

        self.processTapID = tapID

        let systemOutputID = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        let aggregateUID = UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tap-\(process.id)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()

        aggregateDeviceID = AudioObjectID.unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            throw CoreAudioError.audioPropertyError("Failed to create aggregate device: \(err)")
        }

        logger.debug("Created aggregate device #\(self.aggregateDeviceID)")
    }

    /// Prepare system-wide tap that captures all processes
    private func prepareSystemWide() throws {
        errorMessage = nil

        // Get all process IDs for system-wide capture
        let allProcessIDs = try AudioObjectID.readProcessList()
        
        print("🌍 Creating system-wide tap with \(allProcessIDs.count) processes")

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: allProcessIDs)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = muteWhenRunning ? .mutedWhenTapped : .unmuted
        
        var tapID: AUAudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard err == noErr else {
            let errorMsg = "System-wide process tap creation failed with error \(err)"
            logger.error("\(errorMsg)")
            throw CoreAudioError.audioPropertyError(errorMsg)
        }

        logger.debug("Created system-wide process tap #\(tapID)")

        self.processTapID = tapID

        let systemOutputID = try AudioObjectID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        let aggregateUID = UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SystemWideTap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()

        aggregateDeviceID = AudioObjectID.unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            throw CoreAudioError.audioPropertyError("Failed to create system-wide aggregate device: \(err)")
        }

        logger.debug("Created system-wide aggregate device #\(self.aggregateDeviceID)")
    }

    /// Run the tap with the given IO block
    func run(on queue: DispatchQueue, ioBlock: @escaping AudioDeviceIOBlock, invalidationHandler: @escaping InvalidationHandler) throws {
        assert(activated, "run() called with inactive tap!")
        assert(self.invalidationHandler == nil, "run() called with tap already active!")

        errorMessage = nil

        logger.debug("Starting tap run")

        self.invalidationHandler = invalidationHandler

        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else { 
            throw CoreAudioError.audioPropertyError("Failed to create device I/O proc: \(err)") 
        }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else { 
            throw CoreAudioError.audioPropertyError("Failed to start audio device: \(err)") 
        }

        logger.info("Process tap running successfully")
    }

    deinit { 
        invalidate() 
    }
}
