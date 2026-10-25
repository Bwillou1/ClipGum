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

    private var items: [RadialPaletteActionItem] {
        let hasToken = AutoSanitizerService.shared.hasDetectedTokenInClipboard
        return [
            RadialPaletteActionItem(
                title: "Nettoyer & Coller",
                subtitle: "Secrets & ⌘V",
                icon: "sparkles",
                color: .pink,
                action: .pasteCleaned
            ),
            RadialPaletteActionItem(
                title: "Bonsai IA",
                subtitle: "Correction Locale",
                icon: "cpu",
                color: .purple,
                action: .runTransformation(.correction)
            ),
            RadialPaletteActionItem(
                title: "Tableau CSV",
                subtitle: "Markdown / CSV",
                icon: "tablecells",
                color: .blue,
                action: .runTransformation(.convertTable)
            ),
            RadialPaletteActionItem(
                title: hasToken ? "Coller Token" : "Coller Original",
                subtitle: hasToken ? "En clair (Non masqué)" : "Tel quel ⌘V",
                icon: hasToken ? "key.fill" : "doc.on.clipboard",
                color: hasToken ? .yellow : .gray,
                action: .pasteOriginal
            ),
            RadialPaletteActionItem(
                title: "Share-Ready",
                subtitle: "Anonymiser IDs",
                icon: "lock.shield",
                color: .teal,
                action: .runTransformation(.shareReady)
            ),
            RadialPaletteActionItem(
                title: "Masquer Secrets",
                subtitle: "Censurer [REDACTED]",
                icon: "eye.slash",
                color: .orange,
                action: .runTransformation(.secretScrub)
            )
        ]
    }

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

            // Center Hub: Eraser or Token status + Shortcut ⌃X
            VStack(spacing: 3) {
                if AutoSanitizerService.shared.hasDetectedTokenInClipboard {
                    Image(systemName: "key.horizontal.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.yellow)

                    Text("Jeton Détecté")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.yellow)

                    Text("En clair ou Masqué")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "eraser.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("ClipGum")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("⌃X")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.pink)
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
