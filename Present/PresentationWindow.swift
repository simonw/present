import SwiftUI
import AppKit

struct PresentationView: View {
    @Bindable var state: PresentationState
    var onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black

            if let slide = state.currentSlide {
                WebView(url: slide.url, pageZoom: state.zoomLevel)
            } else {
                Text("No slides")
                    .foregroundStyle(.white)
                    .font(.largeTitle)
            }

            // Slide counter overlay
            if !state.slides.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(state.currentIndex + 1) / \(state.slides.count)")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5))
                            .foregroundStyle(.white.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .padding(12)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

class PresentationWindowController {
    private var window: NSWindow?
    private var monitor: Any?

    func open(state: PresentationState) {
        let presentationView = PresentationView(state: state) { [weak self] in
            self?.close(state: state)
        }

        let hostingView = NSHostingView(rootView: presentationView)

        let window = NSWindow(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.level = .statusBar
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)

        self.window = window

        // Key event monitor
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let cmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 123: // Left arrow
                state.goToPrevious()
                return nil
            case 124: // Right arrow
                state.goToNext()
                return nil
            case 53: // Escape
                self?.close(state: state)
                return nil
            case 24, 69 where cmd: // Cmd+= / Cmd+Numpad+
                state.zoomIn()
                return nil
            case 27, 78 where cmd: // Cmd+- / Cmd+Numpad-
                state.zoomOut()
                return nil
            case 29 where cmd: // Cmd+0
                state.zoomReset()
                return nil
            default:
                return event
            }
        }

        state.isPresenting = true
    }

    func close(state: PresentationState) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let window {
            window.close()
        }
        self.window = nil
        state.isPresenting = false
    }
}
