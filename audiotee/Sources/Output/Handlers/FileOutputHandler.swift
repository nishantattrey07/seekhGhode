import AVFoundation
import Foundation

/// Handles audio output by saving to a WAV file
public class FileOutputHandler: AudioOutputHandler {
    private let filePath: String
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?

    public init(filePath: String) {
        self.filePath = filePath
    }

    public func handleStreamStart() {
        Logger.info("Starting file recording", context: ["file_path": filePath])
    }

    public func handleStreamStop() {
        Logger.info("Stopping file recording", context: ["file_path": filePath])
        audioFile = nil
    }

    public func handleMetadata(_ metadata: AudioStreamMetadata) {
        Logger.debug(
            "Received metadata for file recording",
            context: [
                "sample_rate": String(metadata.sampleRate),
                "channels": String(metadata.channelsPerFrame),
                "bits_per_channel": String(metadata.bitsPerChannel),
            ])

        // Create audio format
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: metadata.sampleRate,
            channels: AVAudioChannelCount(metadata.channelsPerFrame),
            interleaved: false
        )

        guard let format = audioFormat else {
            Logger.error("Failed to create audio format for file recording")
            return
        }

        // Create audio file
        do {
            let fileURL = URL(fileURLWithPath: filePath)
            audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            Logger.info("Created audio file for recording", context: ["file_path": filePath])
        } catch {
            Logger.error(
                "Failed to create audio file",
                context: [
                    "file_path": filePath,
                    "error": String(describing: error),
                ])
        }
    }

    public func handleAudioPacket(_ packet: AudioPacket) {
        guard let audioFile = audioFile,
            let audioFormat = audioFormat
        else {
            Logger.error("Audio file or format not initialized")
            return
        }

        // Convert raw audio data to AVAudioPCMBuffer
        let frameCount =
            UInt32(packet.rawAudioData.count)
            / UInt32(audioFormat.streamDescription.pointee.mBytesPerFrame)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)
        else {
            Logger.error("Failed to create PCM buffer for file writing")
            return
        }

        buffer.frameLength = frameCount

        // Copy audio data to buffer
        let audioBytes = packet.rawAudioData
        audioBytes.withUnsafeBytes { rawBytes in
            let floatPointer = rawBytes.bindMemory(to: Float.self)
            buffer.floatChannelData![0].update(
                from: floatPointer.baseAddress!, count: Int(frameCount))
        }

        // Write to file
        do {
            try audioFile.write(from: buffer)
        } catch {
            Logger.error(
                "Failed to write audio data to file",
                context: [
                    "error": String(describing: error)
                ])
        }
    }
}
