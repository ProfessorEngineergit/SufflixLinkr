import Foundation
import CoreServices
import UniformTypeIdentifiers
import AppKit
import Combine

// MARK: - HandlerService (LaunchServices Wrapper)
actor HandlerService {
    
    func getDefaultHandler(for type: UTType) -> AppInfo? {
        guard let handlerBundleID = LSCopyDefaultRoleHandlerForContentType(type.identifier as CFString, .all)?.takeRetainedValue() as String? else {
            return nil
        }
        return resolveApp(bundleID: handlerBundleID)
    }
    
    func getAllHandlers(for type: UTType) -> [AppInfo] {
        guard let handlers = LSCopyAllRoleHandlersForContentType(type.identifier as CFString, .all)?.takeRetainedValue() as? [String] else {
            return []
        }
        return handlers.compactMap { resolveApp(bundleID: $0) }
    }
    
    func setDefaultHandler(bundleID: String, for type: UTType) async -> Result<Void, Error> {
        let result = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString, .all, bundleID as CFString)
        if result == kLSApplicationNotFoundErr {
            return .failure(NSError(domain: "SufflixLinkr", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "App not found."]))
        } else if result != noErr {
            return .failure(NSError(domain: "SufflixLinkr", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Failed to set default handler. Code: \(result)"]))
        }
        return .success(())
    }
    
    private func resolveApp(bundleID: String) -> AppInfo? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            // Fix: 'try?' entfernt, da displayName nicht wirft
            let name = FileManager.default.displayName(atPath: url.path)
            return AppInfo(bundleIdentifier: bundleID, name: name, url: url)
        }
        return nil
    }
}

// MARK: - AppDiscoveryService (Spotlight + Watcher)
class AppDiscoveryService: NSObject {
    private var query: NSMetadataQuery?
    @Published var knownApps: [String: AppInfo] = [:]
    
    func startMonitoring() {
        query = NSMetadataQuery()
        query?.predicate = NSPredicate(format: "kMDItemContentTypeTree == 'com.apple.application-bundle'")
        query?.searchScopes = [NSMetadataQueryLocalComputerScope]
        
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated(_:)), name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(queryUpdated(_:)), name: .NSMetadataQueryDidUpdate, object: query)
        
        query?.start()
    }
    
    @objc private func queryUpdated(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }
        query.disableUpdates()
        
        var apps: [String: AppInfo] = [:]
        for result in query.results {
            if let item = result as? NSMetadataItem,
               let path = item.value(forAttribute: kMDItemPath as String) as? String,
               let bundleID = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String {
                
                let url = URL(fileURLWithPath: path)
                let name = item.value(forAttribute: kMDItemDisplayName as String) as? String ?? url.deletingPathExtension().lastPathComponent
                
                apps[bundleID] = AppInfo(bundleIdentifier: bundleID, name: name, url: url)
            }
        }
        
        DispatchQueue.main.async {
            self.knownApps.merge(apps) { (_, new) in new }
        }
        query.enableUpdates()
    }
    
    func getSupportedTypes(for app: AppInfo) -> [UTType] {
        guard let bundle = Bundle(url: app.url),
              let info = bundle.infoDictionary else { return [] }
        
        var types = Set<UTType>()
        
        if let docTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] {
            for entry in docTypes {
                if let contentTypes = entry["LSItemContentTypes"] as? [String] {
                    contentTypes.compactMap { UTType($0) }.forEach { types.insert($0) }
                }
            }
        }
        
        let declKeys = ["UTImportedTypeDeclarations", "UTExportedTypeDeclarations"]
        for key in declKeys {
            if let decls = info[key] as? [[String: Any]] {
                for entry in decls {
                    if let id = entry["UTTypeIdentifier"] as? String, let type = UTType(id) {
                        types.insert(type)
                    }
                }
            }
        }
        
        return Array(types)
    }
}

// MARK: - ExportImportService
struct ExportImportService {
    
    static func exportToCSV(entries: [FileTypeEntry]) -> String {
        var csv = "# SufflixLinkrExportVersion: 1\n"
        csv += "# ExportDate: \(Date().ISO8601Format())\n"
        csv += "uti,extensions,category,bundleIdentifier,appNameHint,userOverride\n"
        
        for entry in entries {
            let exts = entry.extensions.joined(separator: "|")
            let bundleID = entry.defaultHandler?.bundleIdentifier ?? ""
            let appName = entry.defaultHandler?.name ?? ""
            let override = entry.userOverride ? "true" : "false"
            
            csv += "\(entry.id),\(exts),\(entry.category.rawValue),\(bundleID),\(appName),\(override)\n"
        }
        return csv
    }
    
    static func importFromCSV(url: URL) async throws -> [SlinkrExportRow] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var rows: [SlinkrExportRow] = []
        
        for line in lines {
            if line.starts(with: "#") || line.isEmpty { continue }
            if line.starts(with: "uti,extensions") { continue }
            
            let parts = line.components(separatedBy: ",")
            if parts.count >= 6 {
                let row = SlinkrExportRow(
                    uti: parts[0],
                    extensions: parts[1],
                    category: parts[2],
                    bundleIdentifier: parts[3],
                    appNameHint: parts[4],
                    userOverride: parts[5]
                )
                rows.append(row)
            }
        }
        return rows
    }
}
