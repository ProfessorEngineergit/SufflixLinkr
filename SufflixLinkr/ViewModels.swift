import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
class AppViewModel: ObservableObject {
    @Published var entries: [FileTypeEntry] = []
    @Published var filteredEntries: [FileTypeEntry] = []
    
    // Search & Filter
    @Published var searchText: String = ""
    @Published var selectedCategory: TypeCategory? = nil
    @Published var sortOption: SortOption = .recency
    
    // Mode Switching
    @Published var viewMode: ViewMode = .fileTypes
    @Published var selectedAppID: String?
    
    enum ViewMode {
        case fileTypes
        case apps
    }
    
    // Detail Selection
    @Published var selectedEntryID: String?
    
    // Services
    let handlerService = HandlerService()
    let appDiscovery = AppDiscoveryService()
    
    // Alerting
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false
    
    // New App Detection
    @Published var showNewAppSheet: Bool = false
    @Published var detectedApp: AppInfo?
    @Published var detectedAppSuggestions: [UTType] = []
    
    private var cancellables = Set<AnyCancellable>()
    private var initialAppSnapshot: Set<String> = []
    
    // Computed: Apps List
    var appsList: [AppInfo] {
        return appDiscovery.knownApps.values.sorted { $0.id < $1.id }
    }
    
    enum SortOption {
        case recency, name, extensionName
    }
    
    init() {
        setupSubscriptions()
        appDiscovery.startMonitoring()
        Task {
            await loadAllKnownTypes()
        }
    }
    
    private func setupSubscriptions() {
        Publishers.CombineLatest3($searchText, $selectedCategory, $sortOption)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
            
        appDiscovery.$knownApps
            .dropFirst()
            .sink { [weak self] apps in
                self?.checkForNewApps(apps)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - BIG LIST LOADING
    
    func loadAllKnownTypes() async {
        let allExtensions = [
            // Web & Scripting
            "html", "htm", "css", "scss", "less", "js", "jsx", "ts", "tsx", "php", "asp", "aspx", "jsp",
            "vue", "svelte", "json", "xml", "yaml", "yml", "toml", "wasm",
            
            // Programming / Source
            "swift", "c", "h", "cpp", "hpp", "m", "mm", "cs", "java", "kt", "kts", "go", "rs", "rb", "py",
            "pl", "pm", "lua", "r", "dart", "sh", "bash", "zsh", "fish", "bat", "ps1", "clj", "scala", "fs",
            "sql", "db", "sqlite", "graphql", "cmake", "make", "dockerfile",
            
            // Text / Docs
            "txt", "rtf", "md", "markdown", "tex", "log", "csv", "tsv",
            "pdf", "epub", "mobi", "azw3",
            
            // Office
            "doc", "docx", "dot", "dotx",
            "xls", "xlsx", "xlsm", "csv",
            "ppt", "pptx", "pps", "ppsx",
            "odt", "ods", "odp",
            "pages", "numbers", "key",
            
            // Images
            "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg", "ico", "icns",
            "psd", "ai", "raw", "cr2", "nef", "arw", "dng",
            
            // Audio
            "mp3", "wav", "aac", "m4a", "flac", "ogg", "aiff", "wma", "mid", "midi",
            
            // Video
            "mp4", "mov", "m4v", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "3gp",
            
            // Archives
            "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "iso", "dmg", "pkg",
            
            // 3D & CAD
            "obj", "stl", "fbx", "blend", "dae", "gltf", "glb", "usdz", "step", "stp", "dwg", "dxf",
            
            // System
            "plist", "ini", "cfg", "conf", "properties", "env", "mobileconfig", "cer", "crt", "pem", "ssh"
        ]
        
        var loadedEntries: [FileTypeEntry] = []
        var seenUTIs = Set<String>()
        
        for ext in allExtensions {
            if let type = UTType(filenameExtension: ext) {
                if !seenUTIs.contains(type.identifier) {
                    let entry = await buildEntry(for: type)
                    loadedEntries.append(entry)
                    seenUTIs.insert(type.identifier)
                }
            }
        }
        
        loadedEntries.sort { $0.id < $1.id }
        self.entries = loadedEntries
        self.applyFilters()
        self.initialAppSnapshot = Set(appDiscovery.knownApps.keys)
    }
    
    private func buildEntry(for type: UTType) async -> FileTypeEntry {
        let handler = await handlerService.getDefaultHandler(for: type)
        let exts = type.tags[.filenameExtension] ?? []
        return FileTypeEntry(
            id: type.identifier,
            utType: type,
            extensions: exts,
            category: categorize(type, exts: exts),
            defaultHandler: handler,
            userOverride: false,
            lastTouched: nil
        )
    }
    
    // MARK: - Logic
    
    func applyFilters() {
        var result = entries
        
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.id.localizedCaseInsensitiveContains(searchText) ||
                $0.extensions.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
                ($0.defaultHandler?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        switch sortOption {
        case .name:
            result.sort { $0.id < $1.id }
        case .extensionName:
            result.sort { ($0.extensions.first ?? "") < ($1.extensions.first ?? "") }
        case .recency:
            result.sort {
                ($0.lastTouched ?? Date.distantPast) > ($1.lastTouched ?? Date.distantPast)
            }
        }
        
        self.filteredEntries = result
    }
    
    private func categorize(_ type: UTType, exts: [String]) -> TypeCategory {
        // System / config files first, so they don't get swept into Data or Programming.
        let systemExts = ["plist", "ini", "cfg", "conf", "properties", "env", "mobileconfig", "cer", "crt", "pem", "ssh"]
        if exts.contains(where: { systemExts.contains($0) }) { return .system }

        // Data / DevOps: structured data & database formats.
        let dataExts = ["json", "xml", "yaml", "yml", "toml", "sql", "db", "sqlite", "graphql", "csv", "tsv", "wasm", "dockerfile", "cmake", "make"]
        if exts.contains(where: { dataExts.contains($0) }) { return .data }

        let codeExtensions = ["php", "js", "ts", "jsx", "tsx", "py", "rb", "go", "rs", "java", "kt", "c", "cpp", "h", "swift", "sh", "html", "css"]
        if exts.contains(where: { codeExtensions.contains($0) }) { return .programming }

        if type.conforms(to: .sourceCode) { return .programming }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .audiovisualContent) { return .media }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .pdf) || exts.contains("doc") || exts.contains("xls") { return .office }
        if type.conforms(to: .spreadsheet) || type.conforms(to: .presentation) { return .office }

        let cadExts = ["obj", "stl", "blend", "fbx", "usdz", "step", "stp", "dwg", "dxf", "dae", "gltf", "glb"]
        if exts.contains(where: { cadExts.contains($0) }) { return .cad }

        return .other
    }
    
    func selectEntry(_ id: String) {
        selectedEntryID = id
    }
    
    // MARK: - Handlers
    
    func updateHandler(for type: UTType, to app: AppInfo) {
        Task {
            let result = await handlerService.setDefaultHandler(bundleID: app.bundleIdentifier, for: type)
            // self.showAlert = true
            switch result {
            case .success:
                print("Success setting handler for \(type.identifier) to \(app.name)")
                // Silent
                
                // Update Local UI State
                if let index = entries.firstIndex(where: { $0.id == type.identifier }) {
                    entries[index].defaultHandler = app
                    entries[index].userOverride = true
                    entries[index].lastTouched = Date()
                }
                applyFilters() // Refresh Lists
            case .failure(let error):
                print("Error setting default: \(error.localizedDescription)")
                self.alertMessage = "Failed to update handler: \(error.localizedDescription)"
                self.showAlert = true
            }
        }
    }
    
    // MARK: - New App Detection
    
    private func checkForNewApps(_ currentApps: [String: AppInfo]) {
        let currentIDs = Set(currentApps.keys)
        let newIDs = currentIDs.subtracting(initialAppSnapshot)
        
        if let newID = newIDs.first, let app = currentApps[newID] {
            initialAppSnapshot.insert(newID)
            let types = appDiscovery.getSupportedTypes(for: app)
            if !types.isEmpty {
                self.detectedApp = app
                self.detectedAppSuggestions = types
                self.showNewAppSheet = true
            }
        }
    }
    
    func applySuggestions(for app: AppInfo, types: Set<UTType>) {
        for type in types {
            updateHandler(for: type, to: app)
        }
    }

    // MARK: - Revert / Import

    /// Removes `app` as the default handler for `type` by handing the role to the next
    /// available application. macOS has no "reset to system default" API, so we pick the
    /// first *other* registered handler; if none exists we cannot unset it.
    func revertHandler(for type: UTType, away app: AppInfo) {
        Task {
            let handlers = await handlerService.getAllHandlers(for: type)
            guard let replacement = handlers.first(where: { $0.bundleIdentifier != app.bundleIdentifier }) else {
                self.alertMessage = "No other application can open “\(type.localizedDescription ?? type.identifier)”, so it can't be changed away from \(app.name)."
                self.showAlert = true
                return
            }
            let result = await handlerService.setDefaultHandler(bundleID: replacement.bundleIdentifier, for: type)
            switch result {
            case .success:
                if let index = entries.firstIndex(where: { $0.id == type.identifier }) {
                    entries[index].defaultHandler = replacement
                    entries[index].userOverride = true
                    entries[index].lastTouched = Date()
                }
                applyFilters()
            case .failure(let error):
                self.alertMessage = "Failed to change handler: \(error.localizedDescription)"
                self.showAlert = true
            }
        }
    }

    /// Reads a `.slinkr` file and re-applies every stored default handler, then reports a summary.
    func importSettings(from url: URL) async {
        do {
            let rows = try await ExportImportService.importFromCSV(url: url)
            var applied = 0
            var failed = 0
            var skipped = 0

            for row in rows where !row.bundleIdentifier.isEmpty {
                guard let type = UTType(row.uti) else { skipped += 1; continue }
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.bundleIdentifier) else {
                    failed += 1
                    continue
                }
                let name = row.appNameHint.isEmpty ? FileManager.default.displayName(atPath: appURL.path) : row.appNameHint
                let app = AppInfo(bundleIdentifier: row.bundleIdentifier, name: name, url: appURL)
                let result = await handlerService.setDefaultHandler(bundleID: app.bundleIdentifier, for: type)
                switch result {
                case .success:
                    applied += 1
                    if let index = entries.firstIndex(where: { $0.id == type.identifier }) {
                        entries[index].defaultHandler = app
                        entries[index].userOverride = true
                        entries[index].lastTouched = Date()
                    }
                case .failure:
                    failed += 1
                }
            }

            applyFilters()
            var message = "Imported \(applied) assignment\(applied == 1 ? "" : "s")."
            if failed > 0 { message += " \(failed) failed (app not installed)." }
            if skipped > 0 { message += " \(skipped) skipped (unknown type)." }
            self.alertMessage = message
            self.showAlert = true
        } catch {
            self.alertMessage = "Could not read file: \(error.localizedDescription)"
            self.showAlert = true
        }
    }
    
    func exportSettings() -> URL? {
        let csv = ExportImportService.exportToCSV(entries: entries.filter { $0.userOverride })
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("SufflixLinkr_Export.slinkr")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
