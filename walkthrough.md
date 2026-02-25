# Present: A Code Walkthrough

*2026-02-25T00:20:54Z by Showboat 0.6.1*
<!-- showboat-id: 70db745c-da39-4a05-80bf-a9ce1602d60e -->

## What is Present?

Present is a macOS SwiftUI application for giving presentations where each slide is a URL displayed in a WebView. Instead of PowerPoint or Keynote, you build a presentation as a list of URLs — web pages, images, anything a browser can render — and Present displays them fullscreen with keyboard navigation.

The app was "vibe coded" as a proof of concept for a conference talk. Despite that origin, it's a clean, well-structured ~720 lines of Swift spread across six source files with zero external dependencies.

Key features:
- **Edit mode** with a split-view URL editor and live WebView preview
- **Fullscreen presentation mode** with arrow-key navigation
- **Auto-persistence** to UserDefaults so your slides survive app restarts
- **File I/O** for plain text files (one URL per line)
- **Zoom controls** in both edit and presentation modes
- **Drag-to-reorder** slides in the sidebar
- **Image slides** that detect image URLs and render them centered on black
- **Remote control** via an embedded HTTP server on port 9123, serving a mobile-friendly touch interface

Let's walk through the code file by file, starting from the data model and working outward.

## Project Structure

The entire application lives in six Swift source files plus an entitlements plist. Here's the layout:

```bash
find Present/ -type f -name "*.swift" -o -name "*.entitlements" | sort
```

```output
Present/ContentView.swift
Present/Present.entitlements
Present/PresentApp.swift
Present/PresentationWindow.swift
Present/RemoteServer.swift
Present/Slide.swift
Present/WebView.swift
```

```bash
wc -l Present/*.swift | sort -n
```

```output
   79 Present/Slide.swift
   93 Present/WebView.swift
   95 Present/PresentApp.swift
  102 Present/ContentView.swift
  111 Present/PresentationWindow.swift
  236 Present/RemoteServer.swift
  716 total
```

716 lines total. The heaviest file is `RemoteServer.swift` at 236 lines, largely because it contains an embedded HTML page for the mobile remote control UI. Everything else is under 112 lines.

## 1. The Data Model — `Slide.swift`

This is the foundation of the app. It defines two `@Observable` classes: `Slide` (a single slide) and `PresentationState` (the entire app state).

### The Slide class

A slide is just a UUID and a URL string:

```bash
sed -n "1,12p" Present/Slide.swift
```

```output
import Foundation

@Observable
class Slide: Identifiable {
    let id: UUID
    var url: String

    init(id: UUID = UUID(), url: String = "https://example.com") {
        self.id = id
        self.url = url
    }
}
```

The `@Observable` macro (introduced in iOS 17 / macOS 14) replaces the older `ObservableObject` protocol. It automatically tracks property access and notifies SwiftUI views when values change — no `@Published` wrappers needed. `Identifiable` conformance (via the `id` property) lets SwiftUI's `ForEach` and `List` efficiently diff and animate changes.

Each slide defaults to `https://example.com` — a sensible placeholder when the user clicks "+" to add a new slide.

### PresentationState — the app's brain

This is where all the interesting state lives:

```bash
sed -n "14,26p" Present/Slide.swift
```

```output
@Observable
class PresentationState {
    var slides: [Slide] = [] {
        didSet { saveToDisk() }
    }
    var currentIndex: Int = 0
    var isPresenting: Bool = false
    var zoomLevel: Double = 1.0

    func zoomIn() { zoomLevel = min(zoomLevel + 0.1, 5.0) }
    func zoomOut() { zoomLevel = max(zoomLevel - 0.1, 0.3) }
    func zoomReset() { zoomLevel = 1.0 }

```

Notice the `didSet` on `slides` — every time the array changes (add, remove, reorder), it auto-saves to disk. This is the auto-persistence feature: you never lose your slide list.

The zoom level is clamped between 0.3x and 5.0x, adjusting in 0.1 increments.

### Initialization — restoring from UserDefaults

```bash
sed -n "27,33p" Present/Slide.swift
```

```output
    private static let autosaveKey = "presentAutosavedURLs"

    init() {
        if let urls = UserDefaults.standard.stringArray(forKey: Self.autosaveKey), !urls.isEmpty {
            self.slides = urls.map { Slide(url: $0) }
        }
    }
```

On launch, it checks UserDefaults for a saved array of URL strings under the key `presentAutosavedURLs`. If found, it reconstructs `Slide` objects from them. Note that only the URLs are persisted — the UUIDs are regenerated each launch, which is fine since they're only used for SwiftUI list identity within a session.

### Navigation — wrapping slide traversal

```bash
sed -n "35,48p" Present/Slide.swift
```

```output
    var currentSlide: Slide? {
        guard !slides.isEmpty, currentIndex >= 0, currentIndex < slides.count else { return nil }
        return slides[currentIndex]
    }

    func goToNext() {
        guard !slides.isEmpty else { return }
        currentIndex = (currentIndex + 1) % slides.count
    }

    func goToPrevious() {
        guard !slides.isEmpty else { return }
        currentIndex = (currentIndex - 1 + slides.count) % slides.count
    }
```

Both `goToNext()` and `goToPrevious()` use modular arithmetic to wrap around — pressing Right on the last slide takes you to slide 1, and pressing Left on slide 1 takes you to the last slide. The `+ slides.count` in `goToPrevious()` prevents negative indices.

### File I/O — one URL per line

```bash
sed -n "61,78p" Present/Slide.swift
```

```output
    func loadFromFile(_ url: URL) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let urls = contents.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !urls.isEmpty else { return false }
        slides = urls.map { Slide(url: $0) }
        currentIndex = 0
        return true
    }

    func saveToFile(_ url: URL) -> Bool {
        let contents = slides.map { $0.url }.joined(separator: "\n") + "\n"
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
```

The file format is dead simple: one URL per line in a plain text file. Loading splits on newlines, filters blanks, and creates `Slide` objects. Saving joins URLs with newlines. The `try?` in `loadFromFile` silently handles read errors, and `write(atomically: true)` ensures the file is written completely before replacing the old version. Since assigning to `slides` triggers the `didSet`, loading from a file also auto-saves to UserDefaults.

## 2. The App Entry Point — `PresentApp.swift`

This file bootstraps the application: creating the state, starting the remote server, and wiring up the menu bar.

### App initialization

```bash
sed -n "1,17p" Present/PresentApp.swift
```

```output
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
```

The `@main` attribute marks this as the application entry point. In `init()`, three things happen in sequence:

1. A `PresentationState` is created (which restores any auto-saved URLs from UserDefaults)
2. A `RemoteServer` is created and immediately started, passing it the state object so it can control the presentation
3. Both are stored as `@State` properties using the underscore-prefix initializer syntax (`_state = State(initialValue: s)`), which is the way to set `@State` in an `init()` rather than at the declaration site

The `PresentationWindowController` is also created here — it will manage the fullscreen presentation window later.

### The scene body and notification handling

```bash
sed -n "19,32p" Present/PresentApp.swift
```

```output
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
```

The `WindowGroup` creates the main editor window containing `ContentView`. Two notification observers are attached:

- `.remotePlay` — posted by the remote server when a phone user taps "Start". Opens the fullscreen presentation if not already presenting.
- `.remoteStop` — posted when a phone user taps "Stop". Closes the presentation.

This is how the remote control communicates with the app: the HTTP server posts notifications, and the app's scene body reacts to them. It's a clean decoupling — the server doesn't need a reference to the window controller.

### Menu bar commands

```bash
sed -n "33,72p" Present/PresentApp.swift
```

```output
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
```

Three menu groups are configured:

1. **File menu** (inserted after the default "New" item): Open (Cmd+O) and Save As (Cmd+S) for loading/saving plain text URL lists
2. **View menu**: Zoom In (Cmd+=), Zoom Out (Cmd+-), Actual Size (Cmd+0)
3. **Presentation menu**: Play (Cmd+Shift+P) — disabled when there are no slides

The Play button calls `presentationController.open(state:)` which creates the fullscreen window (covered later in the PresentationWindow section).

### FileDialogHelper — Open and Save panels

```bash
sed -n "75,95p" Present/PresentApp.swift
```

```output
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
```

`FileDialogHelper` is defined as a caseless `enum` — a Swift pattern for creating a namespace that can't be accidentally instantiated. Both methods are `@MainActor` since they present modal UI. They use the standard macOS `NSOpenPanel` / `NSSavePanel`, restricted to plain text files. The default save filename is `presentation.txt`.

## 3. The Edit Mode UI — `ContentView.swift`

This is what the user sees when the app launches: a split-view with a sidebar of URLs on the left and a WebView preview on the right.

### The view structure

```bash
sed -n "1,10p" Present/ContentView.swift
```

```output
import SwiftUI

struct ContentView: View {
    @Bindable var state: PresentationState
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
```

`@Bindable` (the companion to `@Observable`) lets the view create bindings to the state's properties. The local `selection` tracks which slide is highlighted in the sidebar — it's a `UUID?` because `List(selection:)` works with `Identifiable` items.

`NavigationSplitView` gives us the macOS-native sidebar + detail layout automatically.

### The slide list with drag-and-drop

```bash
sed -n "11,36p" Present/ContentView.swift
```

```output
                    ForEach(Array(state.slides.enumerated()), id: \.element.id) { index, slide in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                                .draggable(slide.id.uuidString)
                            TextField("URL", text: Binding(
                                get: { slide.url },
                                set: { slide.url = $0; state.saveToDisk() }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        .tag(slide.id)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedIDString = items.first,
                                  let draggedID = UUID(uuidString: draggedIDString),
                                  let fromIndex = state.slides.firstIndex(where: { $0.id == draggedID }),
                                  let toIndex = state.slides.firstIndex(where: { $0.id == slide.id })
                            else { return false }
                            withAnimation {
                                state.slides.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                            }
                            return true
                        }
                    }
                }
```

Each slide row shows a number and an editable URL text field. The drag-and-drop implementation is worth studying:

- The **slide number** (not the text field) is the drag source via `.draggable(slide.id.uuidString)`
- Each row is a **drop target** via `.dropDestination(for: String.self)`
- When a drop occurs, the handler parses the dragged UUID string, finds both the source and destination indices, and calls `state.slides.move()` inside `withAnimation` for a smooth reorder

The `TextField` binding manually calls `state.saveToDisk()` on every edit. This is necessary because changing a property on a `Slide` object doesn't trigger the `didSet` on the `slides` array (only adding/removing/reordering array elements does).

### Selection sync and the detail panel

```bash
sed -n "37,70p" Present/ContentView.swift
```

```output
                .listStyle(.sidebar)
                .onChange(of: selection) { _, newValue in
                    if let newValue, let index = state.slides.firstIndex(where: { $0.id == newValue }) {
                        state.currentIndex = index
                    }
                }

                HStack {
                    Button(action: addSlide) {
                        Image(systemName: "plus")
                    }
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 500)
        } detail: {
            if let slide = state.currentSlide {
                WebView(url: slide.url, pageZoom: state.zoomLevel)
            } else {
                VStack {
                    Text("No slide selected")
                        .foregroundStyle(.secondary)
                    Text("Add a URL to get started")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
```

When the sidebar selection changes, `.onChange(of: selection)` updates `state.currentIndex` to match. This keeps the state model in sync with the UI selection.

Below the list, "+" and "-" buttons let the user add and remove slides. The "-" button is disabled when nothing is selected.

The `detail:` panel is the right side of the split view. If there's a current slide, it renders a live `WebView` preview with the current zoom level. Otherwise it shows a placeholder message. This means you get a live preview of each URL as you click through your slide list.

### Add and delete logic

```bash
sed -n "81,101p" Present/ContentView.swift
```

```output
    private func addSlide() {
        let slide = Slide()
        state.slides.append(slide)
        selection = slide.id
        state.currentIndex = state.slides.count - 1
    }

    private func deleteSelected() {
        guard let selection else { return }
        if let index = state.slides.firstIndex(where: { $0.id == selection }) {
            state.slides.remove(at: index)
            if state.slides.isEmpty {
                self.selection = nil
                state.currentIndex = 0
            } else {
                let newIndex = min(index, state.slides.count - 1)
                state.currentIndex = newIndex
                self.selection = state.slides[newIndex].id
            }
        }
    }
```

`addSlide()` creates a new `Slide` with the default URL, appends it, and selects it. `deleteSelected()` removes the selected slide and intelligently moves selection to the next available slide (or clears it if the list is empty). The `min(index, slides.count - 1)` ensures we don't select past the end of the list if the last slide was deleted.

## 4. The WebView Wrapper — `WebView.swift`

This file bridges WebKit's `WKWebView` into SwiftUI. It also handles a special case: image URLs get custom rendering with a centered image on a black background.

### The NSViewRepresentable bridge

```bash
sed -n "1,29p" Present/WebView.swift
```

```output
import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let url: String
    var pageZoom: Double = 1.0

    private var isImageURL: Bool {
        let lower = url.lowercased().split(separator: "?").first.map(String.init) ?? url.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".gif") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") || lower.hasSuffix(".svg")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = webView
        context.coordinator.startListening()
        applyContent(in: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        applyContent(in: webView, coordinator: context.coordinator)
    }
```

`NSViewRepresentable` is the protocol for wrapping AppKit views (like `WKWebView`) in SwiftUI. The lifecycle is:

1. `makeCoordinator()` — creates a long-lived helper object (the Coordinator) that survives view updates
2. `makeNSView()` — creates the actual `WKWebView` once, disables back/forward gestures, and starts listening for remote scroll notifications
3. `updateNSView()` — called whenever SwiftUI properties change (URL or zoom level); re-applies the content

The `isImageURL` computed property checks the URL's file extension (stripping query parameters first) to decide between image rendering and normal web page loading.

### Content rendering — images vs. web pages

```bash
sed -n "31,69p" Present/WebView.swift
```

```output
    private func applyContent(in webView: WKWebView, coordinator: Coordinator) {
        if isImageURL {
            webView.pageZoom = 1.0
            let resolvedURL = resolveURL(url)
            if coordinator.lastLoadedURL != resolvedURL {
                coordinator.lastLoadedURL = resolvedURL
                let html = """
                <!DOCTYPE html>
                <html><head><meta name="viewport" content="width=device-width">
                <style>*{margin:0;padding:0;overflow:hidden}body{background:#000;display:flex;align-items:center;justify-content:center;width:100vw;height:100vh}img{max-width:100vw;max-height:100vh;object-fit:contain}</style>
                </head><body><img src="\(resolvedURL)"></body></html>
                """
                webView.loadHTMLString(html, baseURL: nil)
            }
        } else {
            coordinator.lastLoadedURL = nil
            webView.pageZoom = pageZoom
            loadURL(in: webView)
        }
    }

    private func resolveURL(_ raw: String) -> String {
        if let parsed = URL(string: raw), parsed.scheme != nil {
            return raw
        }
        return "https://\(raw)"
    }

    private func loadURL(in webView: WKWebView) {
        guard let parsed = URL(string: url), parsed.scheme != nil else {
            if let parsed = URL(string: "https://\(url)") {
                webView.load(URLRequest(url: parsed))
            }
            return
        }
        if webView.url != parsed {
            webView.load(URLRequest(url: parsed))
        }
    }
```

The `applyContent` method branches on image detection:

**Image URLs** get a custom HTML page loaded via `loadHTMLString`. The HTML uses flexbox to center the image on a black background with `object-fit: contain` so it scales without cropping. The zoom level is forced to 1.0 for images (zooming an image slide doesn't make sense). The coordinator tracks `lastLoadedURL` to avoid reloading the same image on every SwiftUI update.

**Regular URLs** get loaded normally via `WKWebView.load()`. The `loadURL` method adds `https://` if no scheme is present, and checks `webView.url != parsed` to avoid reloading a page that's already displayed. The `pageZoom` property is applied directly — `WKWebView` supports this natively.

### The Coordinator — remote scroll support

```bash
sed -n "71,93p" Present/WebView.swift
```

```output
    class Coordinator {
        weak var webView: WKWebView?
        var lastLoadedURL: String?
        private var observer: NSObjectProtocol?

        func startListening() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: .remoteScroll, object: nil, queue: .main
            ) { [weak self] notification in
                guard let dy = notification.userInfo?["dy"] as? Double,
                      let webView = self?.webView else { return }
                webView.evaluateJavaScript("window.scrollBy(0, \(dy));", completionHandler: nil)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
```

The Coordinator subscribes to `.remoteScroll` notifications. When the remote control's scroll strip is dragged on a phone, the server posts this notification with a `dy` (delta-Y) value. The coordinator receives it and injects `window.scrollBy(0, dy)` as JavaScript into the web view. This lets you scroll a long web page from your phone during a presentation.

The `weak var webView` prevents a retain cycle, and the observer is cleaned up in `deinit` to avoid dangling references.

## 5. Presentation Mode — `PresentationWindow.swift`

This file handles the fullscreen presentation experience. It has two parts: a SwiftUI view for the content, and an AppKit controller for the window itself.

### PresentationView — the fullscreen slide display

```bash
sed -n "1,41p" Present/PresentationWindow.swift
```

```output
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
```

The presentation view is a `ZStack` layering three things:

1. **Black background** — `Color.black` fills the entire screen
2. **WebView content** — the current slide's URL rendered at the current zoom level
3. **Slide counter overlay** — a small "3 / 15" badge in the bottom-right corner, semi-transparent so it doesn't obscure content

The `.ignoresSafeArea()` ensures the content extends to the very edges of the screen — important for true fullscreen. The `onExit` closure is passed in but never directly used in the view body (keyboard handling is done at the window controller level).

### PresentationWindowController — managing the fullscreen window

```bash
sed -n "43,98p" Present/PresentationWindow.swift
```

```output
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
```

The `open()` method does the heavy lifting of entering presentation mode:

1. **Creates the SwiftUI view** and wraps it in an `NSHostingView` (the bridge from SwiftUI to AppKit)
2. **Creates a borderless NSWindow** sized to the main screen. The `.borderless` style removes the title bar and window chrome. `.fullSizeContentView` lets content extend behind where the title bar would be
3. **Configures the window**: `.statusBar` level keeps it above other windows, and `.fullScreenPrimary` enables the macOS fullscreen animation
4. **Shows it** with `makeKeyAndOrderFront` then `toggleFullScreen` to enter macOS native fullscreen

The keyboard monitor is the most interesting part. `NSEvent.addLocalMonitorForEvents` installs a global key handler that intercepts keystrokes before they reach other responders:

- **Left/Right arrows** (keyCodes 123/124): navigate slides
- **Escape** (keyCode 53): exit presentation
- **Cmd+= / Cmd+-** (keyCodes 24/27): zoom in/out
- **Cmd+0** (keyCode 29): reset zoom

Returning `nil` from the handler swallows the event (prevents it from propagating). Returning the event lets it pass through normally.

### Closing the presentation

```bash
sed -n "100,111p" Present/PresentationWindow.swift
```

```output
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
```

`close()` carefully tears down in the right order: first removes the key event monitor (so stale handlers don't fire), then closes the window, nils out the reference, and updates the state. Setting `state.isPresenting = false` lets the remote control UI update its Play/Stop button.

## 6. The Remote Control Server — `RemoteServer.swift`

This is the largest file and the most architecturally interesting. It implements a complete HTTP server using Apple's Network framework, serves a mobile-friendly HTML interface, and bridges HTTP requests to app state changes via NotificationCenter.

### Notification name definitions

```bash
sed -n "1,8p" Present/RemoteServer.swift
```

```output
import Foundation
import Network

extension Notification.Name {
    static let remotePlay = Notification.Name("remotePlay")
    static let remoteStop = Notification.Name("remoteStop")
    static let remoteScroll = Notification.Name("remoteScroll")
}
```

These three notification names are the communication protocol between the server and the rest of the app. They're defined here as extensions on `Notification.Name` so they can be referenced as `.remotePlay`, `.remoteStop`, and `.remoteScroll` throughout the codebase.

### Starting the TCP listener

```bash
sed -n "10,33p" Present/RemoteServer.swift
```

```output
@MainActor
final class RemoteServer {
    private var listener: NWListener?
    private var state: PresentationState?

    func start(state: PresentationState) {
        self.state = state
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: 9123)
        } catch {
            print("RemoteServer: failed to create listener: \(error)")
            return
        }
        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }
        listener?.stateUpdateHandler = { newState in
            print("RemoteServer: \(newState)")
        }
        listener?.start(queue: .main)
    }
```

The server uses Apple's `Network` framework (`NWListener`) rather than a third-party HTTP library. This means zero dependencies for networking.

Key details:
- `@MainActor` ensures all state access happens on the main thread — important since it mutates `PresentationState` which drives the UI
- The listener binds to **TCP port 9123**
- When a new connection arrives, `newConnectionHandler` dispatches to `handleConnection` via a `Task { @MainActor in }` to hop back to the main actor
- The state update handler just logs — useful for debugging but not critical

### Handling HTTP connections

```bash
sed -n "40,54p" Present/RemoteServer.swift
```

```output
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }
            let request = String(data: data, encoding: .utf8) ?? ""
            let response = self.route(request)
            let responseData = Data(response.utf8)
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
```

This is a bare-bones HTTP handler. It reads up to 8KB from the connection (enough for any reasonable HTTP request), converts it to a string, passes it to the router, sends the response, and closes the connection. Every connection is one request-response cycle — no keep-alive. This is perfectly adequate for a local remote control.

### Request routing

```bash
sed -n "56,92p" Present/RemoteServer.swift
```

```output
    private func route(_ raw: String) -> String {
        let firstLine = raw.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let path = parts.count >= 2 ? String(parts[1]) : "/"

        switch path {
        case "/next":
            state?.goToNext()
            return jsonResponse("ok")
        case "/prev":
            state?.goToPrevious()
            return jsonResponse("ok")
        case "/play":
            NotificationCenter.default.post(name: .remotePlay, object: nil)
            return jsonResponse("ok")
        case "/stop":
            NotificationCenter.default.post(name: .remoteStop, object: nil)
            return jsonResponse("ok")
        case "/zoomin":
            state?.zoomIn()
            return jsonResponse("ok")
        case "/zoomout":
            state?.zoomOut()
            return jsonResponse("ok")
        case _ where path.hasPrefix("/scroll"):
            if let query = path.split(separator: "?").last,
               let dyParam = query.split(separator: "=").last,
               let dy = Double(dyParam) {
                NotificationCenter.default.post(name: .remoteScroll, object: nil, userInfo: ["dy": dy])
            }
            return jsonResponse("ok")
        case "/status":
            return statusResponse()
        default:
            return htmlResponse()
        }
    }
```

The router parses HTTP the simplest possible way: grab the first line (`GET /path HTTP/1.1`), split on spaces, take the second part as the path. No URL parsing library needed.

The routing table:
- **`/next`** and **`/prev`** — directly mutate state via `goToNext()`/`goToPrevious()`
- **`/play`** and **`/stop`** — post notifications rather than mutating state directly, because starting/stopping presentation requires the window controller (which lives in `PresentApp`)
- **`/zoomin`** and **`/zoomout`** — directly mutate zoom level
- **`/scroll?dy=N`** — parses the query parameter and posts a `.remoteScroll` notification with the delta value
- **`/status`** — returns JSON with current slide number, total slides, presenting state, and current URL
- **Everything else** (including `/`) — serves the mobile HTML interface

Notice the two communication patterns: some actions mutate state directly (`/next`, `/prev`, zoom), while others use notifications (`/play`, `/stop`, `/scroll`). The difference is about who needs to act — if only the state needs to change, mutate it directly. If a separate component (the window controller or the WebView coordinator) needs to respond, use a notification.

### Response helpers

```bash
sed -n "94,111p" Present/RemoteServer.swift
```

```output
    private func jsonResponse(_ status: String) -> String {
        let body = "{\"status\":\"\(status)\"}"
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private func statusResponse() -> String {
        let index = state?.currentIndex ?? 0
        let total = state?.slides.count ?? 0
        let presenting = state?.isPresenting ?? false
        let slideURL = (state?.currentSlide?.url ?? "").replacingOccurrences(of: "\"", with: "\\\"")
        let body = "{\"slide\":\(index + 1),\"total\":\(total),\"presenting\":\(presenting),\"url\":\"\(slideURL)\"}"
        return "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }

    private func htmlResponse() -> String {
        let body = Self.htmlPage
        return "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
    }
```

The HTTP responses are hand-crafted strings — no HTTP library needed. Each response includes the proper status line, content type, content length, and `Connection: close` header. The JSON is built with string interpolation rather than `JSONEncoder`, which is fine for these tiny payloads. The `statusResponse` method escapes double quotes in the URL to prevent JSON injection.

### The embedded mobile remote control UI

The largest chunk of this file is a static string containing a complete HTML/CSS/JavaScript mobile interface. Here's the structure:

```bash
sed -n "113,170p" Present/RemoteServer.swift
```

```output
    static let htmlPage = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <title>Present Remote</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
        background: #1a1a2e; color: #eee;
        display: flex; flex-direction: column; align-items: center;
        height: 100dvh; padding: 20px; gap: 16px;
        -webkit-user-select: none; user-select: none;
      }
      #status { font-size: 1.6rem; font-weight: 600; text-align: center; min-height: 2em; }
      #url { font-size: 0.85rem; opacity: 0.4; word-break: break-all; text-align: center; max-width: 90vw; }
      .nav-row { display: flex; gap: 16px; width: 100%; max-width: 400px; }
      button {
        flex: 1; padding: 24px 10px; font-size: 1.5rem; font-weight: 600;
        border: none; border-radius: 14px; cursor: pointer;
        transition: transform 0.1s, opacity 0.1s;
        min-height: 80px;
      }
      button:active { transform: scale(0.95); opacity: 0.8; }
      .btn-prev { background: #16213e; color: #e94560; }
      .btn-next { background: #16213e; color: #53d8fb; }
      .btn-play { background: #0f3460; color: #53d8fb; }
      .btn-stop { background: #e94560; color: #fff; }
      .play-row { display: flex; gap: 16px; width: 100%; max-width: 400px; flex: 1; min-height: 0; }
      .play-row button { flex: 1; min-height: 0; height: auto; }
      .scroll-strip {
        width: 50px; flex-shrink: 0; background: #16213e; border-radius: 14px;
        display: flex; align-items: center; justify-content: center;
        color: #555; font-size: 1.2rem; touch-action: none; cursor: grab;
      }
      .scroll-strip:active { cursor: grabbing; background: #1a2740; }
      .zoom-row { display: flex; gap: 16px; width: 100%; max-width: 400px; }
      .btn-zoom { background: #16213e; color: #aaa; font-size: 1.3rem; min-height: 60px; }
      html { touch-action: manipulation; }
    </style>
    </head>
    <body>
      <div id="status">Connecting...</div>
      <div class="nav-row">
        <button class="btn-prev" onclick="send('/prev')">&lsaquo; Prev</button>
        <button class="btn-next" onclick="send('/next')">Next &rsaquo;</button>
      </div>
      <div class="play-row">
        <button id="playBtn" class="btn-play" onclick="togglePlay()">&#9654; Start</button>
        <div class="scroll-strip" id="scrollStrip">&#8597;</div>
      </div>
      <div class="zoom-row">
        <button class="btn-zoom" onclick="send('/zoomout')">A-</button>
        <button class="btn-zoom" onclick="send('/zoomin')">A+</button>
      </div>
      <div id="url"></div>
```

The mobile UI is a dark-themed, touch-optimized interface designed for phone screens. The layout stacks vertically:

1. **Status display** — shows "Slide 3 / 15" (or "Connecting..." / "Disconnected")
2. **Nav row** — large Prev and Next buttons
3. **Play row** — a Play/Stop toggle button alongside a vertical scroll strip
4. **Zoom row** — A- and A+ buttons for text size
5. **URL display** — shows the current slide's URL at low opacity

CSS details worth noting:
- `100dvh` (dynamic viewport height) accounts for mobile browser chrome
- `user-select: none` prevents accidental text selection during frantic button mashing
- `touch-action: manipulation` disables double-tap zoom on the whole page
- The scroll strip uses `touch-action: none` so it can handle raw touch events
- Buttons have a `transform: scale(0.95)` press animation for tactile feedback

### The JavaScript — polling and scroll control

```bash
sed -n "171,235p" Present/RemoteServer.swift
```

```output
      <script>
        let presenting = false;
        function send(path) {
          fetch(path).catch(() => {});
        }
        function togglePlay() {
          send(presenting ? '/stop' : '/play');
        }
        function poll() {
          fetch('/status').then(r => r.json()).then(d => {
            document.getElementById('status').textContent =
              'Slide ' + d.slide + ' / ' + d.total;
            document.getElementById('url').textContent = d.url || '';
            presenting = d.presenting;
            const btn = document.getElementById('playBtn');
            if (presenting) {
              btn.textContent = '\\u25A0 Stop';
              btn.className = 'btn-stop';
            } else {
              btn.textContent = '\\u25B6 Start';
              btn.className = 'btn-play';
            }
          }).catch(() => {
            document.getElementById('status').textContent = 'Disconnected';
          });
        }
        setInterval(poll, 1000);
        poll();

        const strip = document.getElementById('scrollStrip');
        let lastY = null;
        let pendingDy = 0;
        let sendTimer = null;
        function flushScroll() {
          if (pendingDy !== 0) {
            fetch('/scroll?dy=' + Math.round(pendingDy)).catch(() => {});
            pendingDy = 0;
          }
          sendTimer = null;
        }
        strip.addEventListener('touchstart', e => {
          e.preventDefault();
          lastY = e.touches[0].clientY;
          pendingDy = 0;
        }, {passive: false});
        strip.addEventListener('touchmove', e => {
          e.preventDefault();
          const y = e.touches[0].clientY;
          if (lastY !== null) {
            pendingDy += (y - lastY) * 2;
            lastY = y;
            if (!sendTimer) {
              sendTimer = setTimeout(flushScroll, 50);
            }
          }
        }, {passive: false});
        strip.addEventListener('touchend', () => {
          lastY = null;
          flushScroll();
          if (sendTimer) { clearTimeout(sendTimer); sendTimer = null; }
        });
      </script>
    </body>
    </html>
    """
```

The JavaScript has two main systems:

**Status polling**: Every 1 second, `poll()` fetches `/status` and updates the UI. It toggles the Play/Stop button's text, class, and color based on `d.presenting`. If the fetch fails (app closed, network lost), it shows "Disconnected". This is simple polling rather than WebSockets — adequate for a 1-second update interval on a local network.

**Scroll strip**: This is the most sophisticated client-side code. It implements a touch-based scroll controller:

1. `touchstart` — records the initial Y position and resets accumulated delta
2. `touchmove` — calculates how far the finger moved since last event, accumulates it (with a 2x multiplier for sensitivity), and schedules a flush every 50ms
3. `touchend` — immediately flushes any pending scroll and cleans up

The 50ms throttle via `setTimeout` batches rapid touch events into fewer HTTP requests, preventing the server from being overwhelmed by high-frequency touch events. The `Math.round(pendingDy)` keeps the scroll values as integers. The `{passive: false}` option on the event listeners is required to allow `e.preventDefault()`, which stops the browser from scrolling the remote page itself.

## 7. Entitlements — `Present.entitlements`

macOS apps have a sandbox that restricts what they can do. The entitlements file declares the capabilities this app needs:

```bash
cat Present/Present.entitlements
```

```output
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
</dict>
</plist>
```

Four entitlements are enabled:

1. **`app-sandbox`** — the app runs in a sandbox (required for Mac App Store, good practice regardless)
2. **`network.client`** — can make outbound network requests (needed for `WKWebView` to load URLs)
3. **`network.server`** — can listen for incoming connections (needed for the remote control HTTP server on port 9123)
4. **`files.user-selected.read-write`** — can read/write files the user selects via Open/Save dialogs (but not arbitrary filesystem access)

Without the network.server entitlement, the `NWListener` would silently fail. Without network.client, every WebView would show a blank page. These four entitlements are the minimum needed for this app to function.

## How It All Connects

Here's the complete data flow of Present, tracing the path from app launch to a remote-controlled presentation:

**Launch sequence:**
1. `PresentApp.init()` creates `PresentationState` (restores saved URLs from UserDefaults)
2. `RemoteServer` starts listening on port 9123
3. `ContentView` displays the sidebar editor with live WebView preview

**Editing:**
- User types URLs in the sidebar text fields
- Each keystroke updates the `Slide` object and triggers `saveToDisk()` to UserDefaults
- Clicking a slide in the sidebar updates `currentIndex`, which causes the detail panel's `WebView` to load the new URL
- Adding/removing/reordering slides triggers the `slides.didSet` auto-save

**Starting a presentation (local):**
- User presses Cmd+Shift+P → `PresentationWindowController.open()`
- Creates a borderless fullscreen `NSWindow` with the `PresentationView`
- Installs a key event monitor for arrow keys, Escape, and zoom shortcuts

**Starting a presentation (remote):**
- Phone user opens `http://[mac-ip]:9123` → server returns the HTML remote UI
- Phone user taps "Start" → `fetch('/play')` → server posts `.remotePlay` notification
- `PresentApp` receives the notification → calls `presentationController.open()`

**During presentation:**
- Arrow keys (local) or Prev/Next buttons (remote) → `state.goToNext()`/`goToPrevious()`
- State change triggers SwiftUI update → `WebView` loads the new URL
- Remote scroll strip → `/scroll?dy=N` → `.remoteScroll` notification → WebView coordinator injects `window.scrollBy()` JavaScript
- Phone polls `/status` every second to stay in sync

**Exiting:**
- Escape key or remote Stop button → `close()` removes monitor, closes window, sets `isPresenting = false`
- Remote UI updates on next poll to show the Start button again

The architecture is deliberately simple: a single observable state object, notification-based decoupling for cross-component communication, and an embedded HTTP server that requires no external dependencies. At 716 lines of Swift, it's a complete, functional presentation tool.
