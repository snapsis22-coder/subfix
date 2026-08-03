import SubFixUI
import SwiftUI

@main
struct SubFixApp: App {
    var body: some Scene {
        Window("SubFix", id: "principal") {
            VistaPrincipal()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}   // no hay documentos que crear
        }
    }
}
