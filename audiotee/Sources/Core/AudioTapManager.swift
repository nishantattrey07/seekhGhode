import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

class AudioTapManager {
  private var tapID: AudioObjectID?
  private var deviceID: AudioObjectID?

  init() {
    // Empty init - setup happens in setupAudioTap()
  }

  deinit {
    Logger.debug("Cleaning up audio tap manager")

    if let tapID = tapID {
      AudioHardwareDestroyProcessTap(tapID)
      self.tapID = nil
    }

    if let deviceID = deviceID {
      AudioHardwareDestroyAggregateDevice(deviceID)
      self.deviceID = nil
    }
  }

  /// Sets up the audio tap and aggregate device
  func setupAudioTap(with config: TapConfiguration) throws {
    Logger.debug("Setting up audio tap manager")

    tapID = try createSystemAudioTap(with: config)
    deviceID = try createAggregateDevice()

    guard let tapID = tapID, let deviceID = deviceID else {
      throw AudioTeeError.setupFailed
    }

    try addTapToAggregateDevice(tapID: tapID, deviceID: deviceID)

    Logger.debug("Audio tap manager setup complete")
  }

  /// Returns the aggregate device ID for recording
  func getDeviceID() -> AudioObjectID? {
    return deviceID
  }

  private func createSystemAudioTap(with config: TapConfiguration) throws -> AudioObjectID {
    Logger.debug("Creating tap description")
    // Create a tap description
    let description = CATapDescription()

    // Configure the tap to capture all system audio
    description.name = "audiotee-tap"
    description.processes = try translatePIDsToProcessObjects(config.processes)  // Properly translate PIDs
    description.isPrivate = true
    description.muteBehavior = config.muteBehavior.coreAudioValue
    description.isMixdown = true 
    description.isMono = true
    description.isExclusive = config.isExclusive
    description.deviceUID = nil // system default
    description.stream = 0 // first stream of output device

    Logger.debug(
      "Tap description configured",
      context: [
        "name": description.name,
        "processes": String(describing: config.processes),
        "private": String(description.isPrivate),
        "mute": String(describing: description.muteBehavior),
        "mixdown": String(description.isMixdown),
        "mono": String(description.isMono),
        "exclusive": String(description.isExclusive),
      ])

    // Create the tap
    Logger.debug("Creating tap")
    var tapID = AudioObjectID(kAudioObjectUnknown)
    let status = AudioHardwareCreateProcessTap(description, &tapID)

    Logger.debug(
      "AudioHardwareCreateProcessTap completed", context: ["status": String(status)])
    guard status == kAudioHardwareNoError else {
      Logger.error("Failed to create audio tap", context: ["status": String(status)])
      throw AudioTeeError.tapCreationFailed(status)
    }

    // Get the format of the audio tap
    var propertyAddress = getPropertyAddress(selector: kAudioTapPropertyFormat)
    var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.stride)
    var streamDescription = AudioStreamBasicDescription()
    let formatStatus = AudioObjectGetPropertyData(
      tapID, &propertyAddress, 0, nil, &propertySize, &streamDescription)

    if formatStatus == noErr {
      Logger.debug(
        "Tap format retrieved",
        context: [
          "channels": String(streamDescription.mChannelsPerFrame),
          "sample_rate": String(Int(streamDescription.mSampleRate)),
        ])
    }

    return tapID
  }

  private func createAggregateDevice() throws -> AudioObjectID {
    let uid = UUID().uuidString
    let description =
      [
        kAudioAggregateDeviceNameKey: "audiotee-aggregate-device",
        kAudioAggregateDeviceUIDKey: uid,
        kAudioAggregateDeviceSubDeviceListKey: [] as CFArray,
        kAudioAggregateDeviceMasterSubDeviceKey: 0,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceIsStackedKey: false,
      ] as [String: Any]

    var deviceID: AudioObjectID = 0
    let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)

    guard status == kAudioHardwareNoError else {
      Logger.error("Failed to create aggregate device", context: ["status": String(status)])
      throw AudioTeeError.aggregateDeviceCreationFailed(status)
    }

    return deviceID
  }

  private func addTapToAggregateDevice(tapID: AudioObjectID, deviceID: AudioObjectID) throws {
    // Get the tap's UID
    var propertyAddress = getPropertyAddress(selector: kAudioTapPropertyUID)
    var propertySize = UInt32(MemoryLayout<CFString>.stride)
    var tapUID: CFString = "" as CFString
    _ = withUnsafeMutablePointer(to: &tapUID) { tapUID in
      AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, tapUID)
    }

    // Add the tap to the aggregate device
    propertyAddress = getPropertyAddress(
      selector: kAudioAggregateDevicePropertyTapList)
    let tapArray = [tapUID] as CFArray
    propertySize = UInt32(MemoryLayout<CFArray>.stride)

    let status = withUnsafePointer(to: tapArray) { ptr in
      AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, ptr)
    }

    guard status == kAudioHardwareNoError else {
      Logger.error(
        "Failed to add tap to aggregate device", context: ["status": String(status)])
      throw AudioTeeError.tapAssignmentFailed(status)
    }
  }
}