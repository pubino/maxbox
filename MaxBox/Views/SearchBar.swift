import SwiftUI

struct SearchBar: View {
    @Binding var searchQuery: String
    var onSearch: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search messages", text: $searchQuery)
                .textFieldStyle(.plain)
                .onSubmit {
                    onSearch()
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    onSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .frame(width: 220)
    }
}

#Preview {
    SearchBar(searchQuery: .constant("test"), onSearch: {})
        .padding()
}
