import SwiftUI

@main
struct PresentApp: App {
    @State private var state = PresentationState()
    @State private var presentationController = PresentationWindowController()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .onAppear {
                    state.loadFromDisk()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Open...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.plainText]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        _ = state.loadFromFile(url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save As...") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.plainText]
                    panel.nameFieldStringValue = "presentation.txt"
                    if panel.runModal() == .OK, let url = panel.url {
                        _ = state.saveToFile(url)
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandMenu("Presentation") {
                Button("Play") {
                    presentationController.open(state: state)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(state.slides.isEmpty)
            }
        }
    }
}
