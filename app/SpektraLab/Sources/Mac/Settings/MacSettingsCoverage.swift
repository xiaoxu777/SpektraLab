// DEBUG coverage of visible Settings controls. Hidden privacy prose is deliberately not a visible-row claim.
#if DEBUG
import Foundation

@MainActor
enum MacSettingsCoverage {
    enum Fate {
        case shown(MacSettingsSection)
        case shownWhen(MacSettingsSection, when: @MainActor (AppServices) -> Bool, otherwise: String)
    }

    private static func pro(_ section: MacSettingsSection) -> Fate {
        .shownWhen(section, when: { _ in ProMode.shared.on }, otherwise: "Pro only")
    }

    private static var copiedIn: Fate {
        .shownWhen(.sources, when: { m in
            m.library.storage.copiedInFrames + m.library.frames.filter { $0.source == .copiedIn }.count > 0
        }, otherwise: "no copied-in originals")
    }

    static let table: [String: Fate] = [
        "Settings": .shown(.general), "Done": .shown(.general),
        "Language": .shown(.general), "Edition": .shown(.general),
        "Photo location": .shown(.general), "On import": .shown(.general),
        "Appearance": .shown(.appearance), "Mode": .shown(.appearance),
        "System": .shown(.appearance), "Light": .shown(.appearance), "Dark": .shown(.appearance),
        "Background": .shown(.appearance), "Interface scale": .shown(.appearance),
        "New frames": .shown(.develop), "Last used": .shown(.develop),
        "Film": .shown(.develop), "Paper": .shown(.develop),
        "Enable EDR by Default": .shown(.develop),
        "Enable HDR by Default": .shownWhen(.develop, when: { _ in HDRDisplays.shared.showsHDR }, otherwise: "no HDR screen"),
        "Preview size": .shown(.engine), "RAW decoder": .shown(.engine),
        "Crop re-maps the frame": .shown(.engine),
        "Lens Profiles": .shown(.engine), "Installed from Adobe": .shown(.engine),
        "Added by hand": .shown(.engine), "Add .lcp…": .shown(.engine), "Remove": .shown(.engine),
        "Install to SpektraLab": .shown(.engine),
        "Body": .shown(.engine), "No. %@": .shown(.engine), "Another": .shown(.engine),
        "Recipes": pro(.export), "Recipe": pro(.export),
        "New Recipe": pro(.export), "Delete Recipe": pro(.export), "Name": pro(.export),
        "Format": pro(.export), "Size": pro(.export), "Colour": pro(.export), "Quality": pro(.export),
        "Naming": .shown(.export), "Save to": .shown(.export),
        "Watermarks": .shown(.watermarks),
        "Keyboard": .shown(.shortcuts), "Space bar": .shown(.shortcuts),
        "About": .shown(.about), "This app": .shown(.about),
        "Licences and credits": .shown(.about), "SpektraLab engine": .shown(.about), "Film and paper": .shown(.about),
        "Library": .shown(.sources), "Sources": .shown(.sources),
        "Copied into SpektraLab": copiedIn, "%@ frames": copiedIn,
        "Keep a local copy": .shownWhen(.sources, when: { $0.library.linkedFolders.contains { $0.kind == .disk } }, otherwise: "no linked disk folder"),
        "Linked folder actions": .shownWhen(.sources, when: { !$0.library.linkedFolders.isEmpty }, otherwise: "no linked folder"),
        "Storage": .shown(.storage), "%@ on this Mac": .shown(.storage),
        "Copied-in originals": .shown(.storage), "Working copies": .shown(.storage), "Preview copies": .shown(.storage),
        "Own library previews": .shown(.storage), "Full-size renders": .shown(.storage), "Thumbnails and cache": .shown(.storage),
        "Clear Working Copies": .shown(.storage), "Edit history: %@": .shown(.storage), "Clear All…": .shown(.storage),
        "Library previews": .shown(.storage), "Delete Previews": .shown(.storage),
        "Diagnostics": .shown(.diagnostics), "Privacy Policy": .shown(.diagnostics),
        "Export Log Zip": .shown(.diagnostics), "What the log holds": .shown(.diagnostics),
        "This build": .shown(.diagnostics), "Engine": .shown(.diagnostics), "Memory budget": .shown(.diagnostics),
        "Share the log with SpektraLab": .shownWhen(.diagnostics, when: { m in
            #if SPK_LOG_UPLOAD
            return m.diagnostics.canSend
            #else
            return false
            #endif
        }, otherwise: "no log upload endpoint"),
        "Agents": pro(.agents), "Allow agents to use SpektraLab": pro(.agents),
        "Command line": pro(.agents), "MCP server": pro(.agents), "Copy MCP Configuration": pro(.agents),
    ]
}
#endif
