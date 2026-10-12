import SubFixUI
import SwiftUI

@main
struct SubFixApp: App {
    var body: some Scene {
        Window("SubFix", id: "principal") {
            VistaPrincipal()
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}   // no hay documentos que crear
        }
    }
}
