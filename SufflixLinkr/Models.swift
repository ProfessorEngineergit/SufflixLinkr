import Foundation
import UniformTypeIdentifiers
import AppKit

// MARK: - Enums & Structs

enum TypeCategory: String, CaseIterable, Codable, Identifiable {
    case programming = "Programming"
    case office = "Office & Docs"
    case images = "Images"
    case media = "Media"
    case archives = "Archives"
    case data = "Data / DevOps"
    case cad = "3D / CAD"
    case system = "System"
    case other = "Other"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .programming: return "chevron.left.forwardslash.chevron.right"
        case .office: return "doc.text"
        case .images: return "photo"
        case .media: return "film"
        case .archives: return "archivebox"
        case .data: return "cylinder.split.1x2"
        case .cad: return "cube.transparent"
        case .system: return "gearshape"
        case .other: return "questionmark.folder"
        }
    }
}

struct AppInfo: Identifiable, Hashable, Codable {
    let bundleIdentifier: String
    let name: String
    let url: URL
    // Icon wird zur Laufzeit geladen
    
    var id: String { bundleIdentifier }
    
    static let unknown = AppInfo(bundleIdentifier: "unknown", name: "Unknown", url: URL(fileURLWithPath: "/"))
}

struct FileTypeEntry: Identifiable, Hashable {
    let id: String // UTType Identifier (z.B. public.png)
    let utType: UTType
    var extensions: [String]
    var category: TypeCategory
    var defaultHandler: AppInfo?
    var userOverride: Bool
    var lastTouched: Date?
    
    var displayName: String {
        utType.localizedDescription ?? id
    }
}

extension UTType {
    /// Exported document type for `.slinkr` configuration files. Declared in Info.plist
    /// (UTExportedTypeDeclarations); `exportedAs` guarantees a non-nil type even before
    /// LaunchServices has registered the app, so it is safe to force-free of crashes.
    static let slinkr = UTType(exportedAs: "Bahrian-Novotny.SufflixLinkr.slinkr")
}

struct SlinkrExportRow {
    let uti: String
    let extensions: String
    let category: String
    let bundleIdentifier: String
    let appNameHint: String
    let userOverride: String
}
