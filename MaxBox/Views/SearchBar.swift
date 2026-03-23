import SwiftUI

struct SearchBar: View {
    @Binding var searchQuery: String
    var onSearch: () -> Void

    @State private var isExpanded = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isExpanded {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)

                TextField("Search messages", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { onSearch() }
                    .transition(.opacity)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        onSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .transition(.opacity)
                }

                Button {
                    onSearch()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Search")
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded = true
                    }
                    isFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Search messages")
                .transition(.opacity)
            }
        }
        .padding(6)
        .background(
            isExpanded
                ? AnyShapeStyle(.quaternary)
                : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .frame(width: isExpanded ? 220 : nil)
        .animation(.easeInOut(duration: 0.25), value: isExpanded)
        .onExitCommand {
            collapse()
        }
        .onChange(of: isFocused) {
            if !isFocused && searchQuery.isEmpty {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded = false
                }
            }
        }
    }

    private func collapse() {
        searchQuery = ""
        onSearch()
        withAnimation(.easeInOut(duration: 0.25)) {
            isExpanded = false
        }
        isFocused = false
    }
}

#Preview("Collapsed") {
    SearchBar(searchQuery: .constant(""), onSearch: {})
        .padding()
}

#Preview("Expanded") {
    SearchBar(searchQuery: .constant("test query"), onSearch: {})
        .padding()
}
