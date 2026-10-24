import SwiftUI

@MainActor
struct LicensesView: View {
    @State private var selected: LicenseEntry? = LicenseCatalog.entries[0]
    private var currentSelection: LicenseEntry { selected ?? LicenseCatalog.entries[0] }

    var body: some View {
        HStack(spacing: 0) {
            List(LicenseCatalog.entries, selection: $selected) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.title).font(.headline)
                    Text(entry.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .tag(Optional(entry))
                .padding(.vertical, 3)
            }
            .frame(width: 245)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(currentSelection.title).font(.title3.bold())
                Text(currentSelection.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    Text(currentSelection.loadText())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 10)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
