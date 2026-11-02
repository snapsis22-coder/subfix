import SubFixUI
import SwiftUI

@main
struct SubFixApp: App {
    var body: some Scene {
        Window("SubFix", id: "principal") {
            VistaPrincipal()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1040, height: 720)
        .windowStyle(.hiddenTitleBar)          // el degradado sube hasta los semáforos
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}   // no hay documentos que crear
            CommandGroup(after: .appInfo) { ComandosDeActualizacion() }
        }
    }
}
