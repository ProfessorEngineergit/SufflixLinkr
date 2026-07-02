//
//  MainWindow.swift
//  SufflixLinkr
//
//  Created by Bahrian Novotny on 25.01.26.
//


import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Main Window Structure

struct MainWindow: View {
    @EnvironmentObject var vm: AppViewModel
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            if vm.viewMode == .apps {
                AppListContent()
            } else {
                TypeListView()
            }
        } detail: {
            if vm.viewMode == .apps {
                if let appID = vm.selectedAppID,
                   let app = vm.appsList.first(where: { $0.id == appID }) {
                    AppDetailView(app: app)
                } else {
                    Text("Select an App")
                        .foregroundStyle(.secondary)
                }
            } else {
                if let selectedID = vm.selectedEntryID,
                   let entry = vm.entries.first(where: { $0.id == selectedID }) {
                    DetailPane(entry: entry)
                } else {
                    Text("Select a file type")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $vm.showNewAppSheet) {
            NewAppSheet()
        }
        .alert("SufflixLinkr", isPresented: $vm.showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.alertMessage)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Import .slinkr…", action: { importAction() })
                    Button("Export .slinkr…", action: { exportAction() })
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    func exportAction() {
        guard let url = vm.exportSettings() else {
            vm.alertMessage = "No user overrides to export yet."
            vm.showAlert = true
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.slinkr]
        panel.nameFieldStringValue = "MyConfig.slinkr"
        panel.begin { response in
            if response == .OK, let target = panel.url {
                // Overwrite any existing file at the chosen location.
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: url, to: target)
            }
        }
    }

    func importAction() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.slinkr]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { await vm.importSettings(from: url) }
            }
        }
    }
}

// MARK: - Components

struct SidebarView: View {
    @EnvironmentObject var vm: AppViewModel
    
    var body: some View {
        VStack {
            Picker("Mode", selection: $vm.viewMode) {
                Text("File Types").tag(AppViewModel.ViewMode.fileTypes)
                Text("Applications").tag(AppViewModel.ViewMode.apps)
            }
            .pickerStyle(.segmented)
            .padding()
            
            if vm.viewMode == .fileTypes {
                List(selection: $vm.selectedCategory) {
                    Label("All", systemImage: "square.grid.2x2")
                        .tag(Optional<TypeCategory>.none) // Represents 'All'
                    
                    Text("Categories").font(.caption).foregroundStyle(.secondary)
                    ForEach(TypeCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.iconName)
                            .tag(cat)
                    }
                    
                    Divider()
                    
                    Text("Filters").font(.caption).foregroundStyle(.secondary)
                    Picker("Sort", selection: $vm.sortOption) {
                        Text("Recent").tag(AppViewModel.SortOption.recency)
                        Text("Name").tag(AppViewModel.SortOption.name)
                        Text("Extension").tag(AppViewModel.SortOption.extensionName)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

struct TypeListView: View {
    @EnvironmentObject var vm: AppViewModel
    
    var body: some View {
        List(selection: $vm.selectedEntryID) {
            ForEach(vm.filteredEntries) { entry in
                FileTypeRow(entry: entry)
                    .tag(entry.id)
                    .contextMenu {
                        Button("Copy UTI") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.id, forType: .string) }
                    }
            }
        }
        .searchable(text: $vm.searchText)
        // WICHTIG: Damit die Selection funktioniert:
        .onChange(of: vm.selectedEntryID) { _, newValue in
            if let id = newValue { vm.selectEntry(id) }
        }
    }
}

struct FileTypeRow: View {
    let entry: FileTypeEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.displayName).font(.headline)
                Text(entry.extensions.map { ".\($0)" }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let handler = entry.defaultHandler {
                HStack {
                    AsyncIcon(url: handler.url)
                        .frame(width: 24, height: 24)
                    Text(handler.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
                .background(.ultraThinMaterial.opacity(0.5))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DetailPane: View {
    let entry: FileTypeEntry
    @EnvironmentObject var vm: AppViewModel
    @State private var availableApps: [AppInfo] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(entry.displayName).font(.largeTitle).bold()
                    // Korrigiert: .font(.caption.monospaced())
                    Text(entry.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Image(systemName: "doc")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(.blue.opacity(0.8))
            }
            
            Divider()
            
            VStack(alignment: .leading) {
                Text("Default Application").font(.headline)
                
                HStack {
                    if let current = entry.defaultHandler {
                        AsyncIcon(url: current.url)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading) {
                            Text(current.name).font(.title3)
                            Text(current.url.path).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("None set")
                    }
                    
                    Spacer()
                    
                    Menu("Change...") {
                        ForEach(availableApps) { app in
                            Button {
                                vm.updateHandler(for: entry.utType, to: app)
                            } label: {
                                HStack {
                                    Text(app.name)
                                    if app.bundleIdentifier == entry.defaultHandler?.bundleIdentifier {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                }
                .padding()
                .liquidGlass()
            }
            
            VStack(alignment: .leading) {
                Text("Extensions").font(.headline)
                FlowLayout(items: entry.extensions) { ext in
                    Text(".\(ext)")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding(30)
        .task(id: entry.id) {
            availableApps = await vm.handlerService.getAllHandlers(for: entry.utType)
        }
    }
}

struct NewAppSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedTypes: Set<UTType> = []
    
    var body: some View {
        VStack(spacing: 20) {
            if let app = vm.detectedApp {
                AsyncIcon(url: app.url).frame(width: 80, height: 80)
                Text("New App Detected: \(app.name)").font(.title)
                
                Text("SufflixLinkr found types that this app can handle.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                List {
                    ForEach(vm.detectedAppSuggestions, id: \.identifier) { type in
                        Toggle(isOn: Binding(
                            get: { selectedTypes.contains(type) },
                            set: { isSelected in
                                if isSelected { selectedTypes.insert(type) }
                                else { selectedTypes.remove(type) }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(type.localizedDescription ?? type.identifier)
                                Text(type.identifier).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 300)
                .cornerRadius(10)
                
                HStack {
                    Button("Ignore") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Apply Selected") {
                        if let app = vm.detectedApp {
                            vm.applySuggestions(for: app, types: selectedTypes)
                        }
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}

// MARK: - New App Views
struct AppListContent: View {
    @EnvironmentObject var vm: AppViewModel
    
    var body: some View {
        List(selection: $vm.selectedAppID) {
            ForEach(vm.appsList) { app in
                HStack {
                    AsyncIcon(url: app.url)
                        .frame(width: 24, height: 24)
                    Text(app.name)
                }
                .tag(app.id)
            }
        }
    }
}

struct AppDetailView: View {
    let app: AppInfo
    @EnvironmentObject var vm: AppViewModel

    // Grouped by Category — read directly from the view model so the UI always
    // reflects the live LaunchServices state (changes are applied immediately).
    var groupedEntries: [TypeCategory: [FileTypeEntry]] {
        Dictionary(grouping: vm.entries, by: { $0.category })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                AsyncIcon(url: app.url)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading) {
                    Text(app.name).font(.largeTitle).bold()
                    Text(app.url.path).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            Divider()

            // List
            List {
                ForEach(TypeCategory.allCases) { category in
                    if let items = groupedEntries[category], !items.isEmpty {
                        Section(header: HStack {
                            Text(category.rawValue)
                            Spacer()
                            Button("Select All") {
                                for item in items {
                                    vm.updateHandler(for: item.utType, to: app)
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }) {
                            ForEach(items) { entry in
                                AppTypeRow(entry: entry, isSelected: entry.defaultHandler?.bundleIdentifier == app.bundleIdentifier) { isActive in
                                    if isActive {
                                        vm.updateHandler(for: entry.utType, to: app)
                                    } else {
                                        vm.revertHandler(for: entry.utType, away: app)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct AppTypeRow: View {
    let entry: FileTypeEntry
    let isSelected: Bool
    let onChange: (Bool) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.displayName).font(.headline)
                Text("." + entry.extensions.joined(separator: ", ."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { onChange($0) }
            ))
            //.toggleStyle(.switch) // Use switch or the specific Liquid style requested? "Standard Liquid Glass Toggles"
            // Assuming default toggle for now as no custom toggle code provided
        }
    }
}

// MARK: - Helpers

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

extension View {
    func liquidGlass() -> some View {
        modifier(GlassBackground())
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct AsyncIcon: View {
    let url: URL
    @State private var icon: NSImage?
    
    var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon).resizable()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}

struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}
