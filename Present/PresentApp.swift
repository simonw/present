import SwiftUI
import Combine
import UniformTypeIdentifiers

@main
struct PresentApp: App {
    @State private var state: PresentationState
    @State private var presentationController = PresentationWindowController()
    @State private var server: RemoteServer

    init() {
        let s = PresentationState()
        let srv = RemoteServer()
        srv.start(state: s)
        _state = State(initialValue: s)
        _server = State(initialValue: srv)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .onReceive(NotificationCenter.default.publisher(for: .remotePlay)) { _ in
                    if !state.isPresenting {
                        presentationController.open(state: state)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .remoteStop)) { _ in
                    if state.isPresenting {
                        presentationController.close(state: state)
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Open...") {
                    FileDialogHelper.open(state: state)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save As...") {
                    FileDialogHelper.save(state: state)
                }
                .keyboardShortcut("s", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Zoom In") {
                    state.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    state.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    state.zoomReset()
                }
                .keyboardShortcut("0", modifiers: .command)
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

enum FileDialogHelper {
    @MainActor
    static func open(state: PresentationState) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = state.loadFromFile(url)
        }
    }

    @MainActor
    static func save(state: PresentationState) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "presentation.txt"
        if panel.runModal() == .OK, let url = panel.url {
            _ = state.saveToFile(url)
        }
    }
}
