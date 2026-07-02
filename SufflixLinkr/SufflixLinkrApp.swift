import SwiftUI

@main
struct SufflixLinkrApp: App {
    // Hier wird das ViewModel einmalig erstellt
    @StateObject var viewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            // Hier wird das Hauptfenster aufgerufen
            MainWindow()
                .environmentObject(viewModel)
                .frame(minWidth: 900, minHeight: 600)
                // "sidebar" Material sorgt für den modernen macOS-Hintergrund
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                // Doppelklick auf eine .slinkr-Datei im Finder importiert die Konfiguration.
                .onOpenURL { url in
                    Task { await viewModel.importSettings(from: url) }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
