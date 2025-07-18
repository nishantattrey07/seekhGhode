import Foundation
import AppKit
import AudioToolbox

/// Represents an audio process that can be tapped
struct AudioProcess: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case process
        case app
    }
    
    var id: pid_t
    var kind: Kind
    var name: String
    var audioActive: Bool
    var bundleID: String?
    var bundleURL: URL?
    var objectID: AudioObjectID
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(objectID)
    }
    
    // Implement Equatable
    static func == (lhs: AudioProcess, rhs: AudioProcess) -> Bool {
        return lhs.id == rhs.id && lhs.objectID == rhs.objectID
    }
}

/// Groups related audio processes
struct AudioProcessGroup: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var processes: [AudioProcess]
}

extension AudioProcess.Kind {
    var defaultIcon: NSImage {
        switch self {
        case .process: NSWorkspace.shared.icon(for: .unixExecutable)
        case .app: NSWorkspace.shared.icon(for: .applicationBundle)
        }
    }
}

extension AudioProcess {
    var icon: NSImage {
        guard let bundleURL else { return kind.defaultIcon }
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        image.size = NSSize(width: 32, height: 32)
        return image
    }
}

// MARK: - AudioProcess Creation

extension AudioObjectID {
    func toAudioProcess(runningApplications: [NSRunningApplication]) throws -> AudioProcess {
        let pid = try readProcessPID()
        let bundleID = readProcessBundleID()
        let isRunning = readProcessIsRunning()
        
        let app = runningApplications.first { $0.processIdentifier == pid }
        
        let kind: AudioProcess.Kind = app?.bundleURL != nil ? .app : .process
        let name = app?.localizedName ?? "Process \(pid)"
        
        return AudioProcess(
            id: pid,
            kind: kind,
            name: name,
            audioActive: isRunning,
            bundleID: bundleID,
            bundleURL: app?.bundleURL,
            objectID: self
        )
    }
}

// MARK: - AudioProcessGroup Helpers

extension AudioProcessGroup {
    static func groups(with processes: [AudioProcess]) -> [AudioProcessGroup] {
        let grouped = Dictionary(grouping: processes) { process in
            process.kind == .app ? "Applications" : "Processes"
        }
        
        return grouped.compactMap { key, processes in
            guard !processes.isEmpty else { return nil }
            return AudioProcessGroup(
                id: key,
                title: key,
                processes: processes.sorted { $0.name < $1.name }
            )
        }.sorted { $0.title < $1.title }
    }
}
