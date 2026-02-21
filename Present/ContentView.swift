import SwiftUI

struct ContentView: View {
    @Bindable var state: PresentationState
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(Array(state.slides.enumerated()), id: \.element.id) { index, slide in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            TextField("URL", text: Binding(
                                get: { slide.url },
                                set: { slide.url = $0; state.saveToDisk() }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        .tag(slide.id)
                    }
                    .onMove { source, destination in
                        state.slides.move(fromOffsets: source, toOffset: destination)
                    }
                }
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
                WebView(url: slide.url)
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
        .onAppear {
            if state.slides.isEmpty {
                addSlide()
            }
            if let first = state.slides.first {
                selection = first.id
            }
        }
    }

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
}
