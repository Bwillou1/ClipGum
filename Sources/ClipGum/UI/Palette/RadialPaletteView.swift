import SwiftUI

struct RadialPaletteActionItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: PaletteAction
}

@MainActor
struct RadialPaletteView: View {
    @ObservedObject var model: PaletteModel
    let onAction: (PaletteAction) -> Void
    let onDismiss: () -> Void

    @State private var hoveredIndex: Int? = nil
    @State private var appearanceScale: CGFloat = 0.6
    @State private var appearanceOpacity: Double = 0.0

    private let items: [RadialPaletteActionItem] = [
        RadialPaletteActionItem(
            title: "Clean & Paste",
            subtitle: "Redact & ⌘V",
            icon: "sparkles",
            color: .pink,
            action: .pasteCleaned
        ),
        RadialPaletteActionItem(
            title: "Bonsai AI",
            subtitle: "Smart Correct",
            icon: "cpu",
            color: .purple,
            action: .runTransformation(.correction)
        ),
        RadialPaletteActionItem(
            title: "Table Convert",
            subtitle: "CSV / Markdown",
            icon: "tablecells",
            color: .blue,
            action: .runTransformation(.convertTable)
        ),
        RadialPaletteActionItem(
            title: "Paste Original",
            subtitle: "Unchanged ⌘V",
            icon: "doc.on.clipboard",
            color: .gray,
            action: .pasteOriginal
        ),
        RadialPaletteActionItem(
            title: "Share-Ready",
            subtitle: "Anonymize IDs",
            icon: "lock.shield",
            color: .teal,
            action: .runTransformation(.shareReady)
        ),
        RadialPaletteActionItem(
            title: "Secret Scrub",
            subtitle: "Scrub Tokens",
            icon: "eye.slash",
            color: .orange,
            action: .runTransformation(.secretScrub)
        )
    ]

    private let wheelRadius: CGFloat = 115

    var body: some View {
        ZStack {
            // Background blur ring & dark aesthetic
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 320, height: 320)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.6), Color.cyan.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)

            // Outer decorative ring
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                .frame(width: 250, height: 250)

            // Radial Action Buttons around mouse center
            ForEach(0..<items.count, id: \.self) { index in
                let angle = angleForIndex(index)
                let x = wheelRadius * cos(angle)
                let y = wheelRadius * sin(angle)
                let item = items[index]
                let isHovered = hoveredIndex == index

                Button {
                    onAction(item.action)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: isHovered ? 20 : 16, weight: .bold))
                            .foregroundStyle(item.color)
                        Text(item.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        Text(item.subtitle)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 82, height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isHovered ? item.color.opacity(0.25) : Color.black.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(isHovered ? item.color : Color.white.opacity(0.15), lineWidth: isHovered ? 1.5 : 1)
                            )
                    )
                    .scaleEffect(isHovered ? 1.12 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
                }
                .buttonStyle(.plain)
                .position(x: 160 + x, y: 160 + y)
                .onHover { inside in
                    hoveredIndex = inside ? index : (hoveredIndex == index ? nil : hoveredIndex)
                }
            }

            // Center Hub: Eraser icon + Quick preview
            VStack(spacing: 4) {
                Image(systemName: "eraser.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("ClipGum")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)

                if let preview = model.preview {
                    Text(preview.deterministicBaseline.cleanedText.prefix(28) + (preview.deterministicBaseline.cleanedText.count > 28 ? "…" : ""))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 70)
                }
            }
            .frame(width: 80, height: 80)
            .background(
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .pink.opacity(0.3), radius: 8)
            )
            .onTapGesture {
                onDismiss()
            }
        }
        .frame(width: 340, height: 340)
        .scaleEffect(appearanceScale)
        .opacity(appearanceOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                appearanceScale = 1.0
                appearanceOpacity = 1.0
            }
        }
    }

    private func angleForIndex(_ index: Int) -> CGFloat {
        // Arrange items clockwise starting from 30 degrees
        let step = (2.0 * .pi) / CGFloat(items.count)
        return CGFloat(index) * step - (.pi / 2.0)
    }
}
