import Foundation
import AudioToolbox
import OSLog
import AVFoundation

/// Handles recording from a ProcessTap to an audio file
/// Adapted from AudioCap: https://github.com/insidegui/AudioCap
@available(macOS 14.2, *)
class ProcessTapRecorder {

    let fileURL: URL
    let process: AudioProcess
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)
    private let logger: Logger

    private weak var _tap: ProcessTap?

    private(set) var isRecording = false
    private var callbackCount = 0

    init(fileURL: URL, tap: ProcessTap) {
        self.process = tap.process
        self.fileURL = fileURL
        self._tap = tap
        self.logger = Logger(subsystem: "AudioRecorderCLI", category: "ProcessTapRecorder(\(fileURL.lastPathComponent))")
    }

    private var tap: ProcessTap {
        get throws {
            guard let _tap else { 
                throw CoreAudioError.audioPropertyError("Process tap unavailable") 
            }
            return _tap
        }
    }

    private var currentFile: AVAudioFile?

    /// Start recording
    func start() throws {
        logger.debug("Starting recording to \(self.fileURL.path)")
        
        guard !isRecording else {
            logger.warning("start() called while already recording")
            return
        }

        let tap = try tap

        if !tap.activated { 
            tap.activate() 
        }

        guard var streamDescription = tap.tapStreamDescription else {
            throw CoreAudioError.audioPropertyError("Tap stream description not available.")
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CoreAudioError.audioPropertyError("Failed to create AVAudioFormat.")
        }

        logger.info("Using audio format: \(format)")

        let settings: [String: Any] = [
            AVFormatIDKey: streamDescription.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        
        let file = try AVAudioFile(
            forWriting: fileURL, 
            settings: settings, 
            commonFormat: .pcmFormatFloat32, 
            interleaved: format.isInterleaved
        )

        self.currentFile = file

        try tap.run(on: queue) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self, let currentFile = self.currentFile else { return }
            
            // Debug: Check if we're getting callbacks
            self.callbackCount += 1
            if self.callbackCount % 100 == 0 {
                self.logger.debug("IOProc callback #\(self.callbackCount) received")
            }
            
            do {
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, 
                    bufferListNoCopy: inInputData, 
                    deallocator: nil
                ) else {
                    throw CoreAudioError.audioPropertyError("Failed to create PCM buffer")
                }

                try currentFile.write(from: buffer)
            } catch {
                self.logger.error("Error writing audio: \(error)")
            }
        } invalidationHandler: { [weak self] tap in
            guard let self else { return }
            handleInvalidation()
        }

        isRecording = true
        logger.info("Recording started successfully")
    }

    /// Stop recording
    func stop() {
        guard isRecording else { return }

        logger.debug("Stopping recording")

        do {
            currentFile = nil
            isRecording = false
            
            try tap.invalidate()
            logger.info("Recording stopped")
        } catch {
            logger.error("Stop failed: \(error)")
        }
    }

    private func handleInvalidation() {
        guard isRecording else { return }
        logger.debug("Handling tap invalidation")
        // Additional cleanup if needed
    }
}
