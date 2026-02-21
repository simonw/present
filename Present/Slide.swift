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

    private static let autosaveKey = "presentAutosavedURLs"

    init() {
        if let urls = UserDefaults.standard.stringArray(forKey: Self.autosaveKey), !urls.isEmpty {
            self.slides = urls.map { Slide(url: $0) }
        }
    }

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

    func saveToDisk() {
        let urls = slides.map { $0.url }
        UserDefaults.standard.set(urls, forKey: Self.autosaveKey)
    }

    func loadFromDisk() {
        guard let urls = UserDefaults.standard.stringArray(forKey: Self.autosaveKey), !urls.isEmpty else { return }
        slides = urls.map { Slide(url: $0) }
        currentIndex = 0
    }

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
}
