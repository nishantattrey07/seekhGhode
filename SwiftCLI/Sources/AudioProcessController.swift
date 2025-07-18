import Foundation
import AppKit
import AudioToolbox
import OSLog

/// Manages discovery and listing of audio processes
class AudioProcessController {
    
    private let logger = Logger(subsystem: "AudioRecorderCLI", category: "AudioProcessController")
    
    private(set) var processes = [AudioProcess]() {
        didSet {
            guard processes != oldValue else { return }
            processGroups = AudioProcessGroup.groups(with: processes)
        }
    }
    
    private(set) var processGroups = [AudioProcessGroup]()
    
    /// Reload and discover all current audio processes
    func reloadProcesses() {
        logger.debug("Reloading audio processes...")
        
        let runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        
        reload(apps: runningApps)
    }
    
    /// Get a list of all available audio processes (including system-wide option)
    func getAvailableProcesses() -> [AudioProcess] {
        reloadProcesses()
        
        // Add system-wide option as first item
        var allProcesses = [AudioProcess]()
        let systemWideProcess = AudioProcess(
            id: 0,
            kind: .process,
            name: "System-Wide Audio",
            audioActive: true,
            bundleID: "system.all",
            bundleURL: nil,
            objectID: 0
        )
        allProcesses.append(systemWideProcess)
        allProcesses.append(contentsOf: processes)
        
        return allProcesses
    }
    
    /// Find a specific process by name
    func findProcess(named name: String) -> AudioProcess? {
        reloadProcesses()
        return processes.first { $0.name.lowercased().contains(name.lowercased()) }
    }
    
    /// Find all processes (system-wide capture)
    func getAllProcesses() -> [AudioObjectID] {
        do {
            return try AudioObjectID.readProcessList()
        } catch {
            logger.error("Failed to get all processes: \(error)")
            return []
        }
    }
    
    private func reload(apps: [NSRunningApplication]) {
        logger.debug("Reloading with \(apps.count) running applications")
        
        do {
            let objectIdentifiers = try AudioObjectID.readProcessList()
            
            let updatedProcesses: [AudioProcess] = objectIdentifiers.compactMap { objectID in
                do {
                    let process = try objectID.toAudioProcess(runningApplications: apps)
                    
                    #if DEBUG
                    logger.debug("Found process: \(process.name) (PID: \(process.id))")
                    #endif
                    
                    return process
                } catch {
                    logger.warning("Failed to initialize process with object ID #\(objectID): \(error)")
                    return nil
                }
            }
            
            self.processes = updatedProcesses
            logger.info("Loaded \(updatedProcesses.count) audio processes")
            
        } catch {
            logger.error("Failed to reload processes: \(error)")
            self.processes = []
        }
    }
}

// MARK: - CLI Helper Functions

extension AudioProcessController {
    
    /// Print all available processes to console
    func listProcesses() {
        let allProcesses = getAvailableProcesses()
        
        if allProcesses.isEmpty {
            print("❌ No audio processes found")
            return
        }
        
        print("📱 Available Audio Processes:")
        print()
        
        // Show system-wide option first
        let systemWideProcess = allProcesses.first { $0.name == "System-Wide Audio" }
        if let systemWide = systemWideProcess {
            print("📂 System Options:")
            let status = systemWide.audioActive ? "🎵 ACTIVE" : "⏸️  INACTIVE"
            print("  • \(systemWide.name) (All Processes) - \(status)")
            print()
        }
        
        // Show regular process groups
        for group in processGroups {
            print("📂 \(group.title):")
            for process in group.processes {
                let status = process.audioActive ? "🎵 ACTIVE" : "⏸️  INACTIVE"
                print("  • \(process.name) (PID: \(process.id)) - \(status)")
            }
            print()
        }
    }
    
    /// Get process for system-wide recording
    func getSystemWideProcesses() -> [AudioObjectID] {
        return getAllProcesses()
    }
}
