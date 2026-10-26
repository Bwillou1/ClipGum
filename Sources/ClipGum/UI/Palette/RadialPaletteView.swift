import SwiftUI

struct RadialPaletteActionItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let action: PaletteAction
}

@MainActor
struct RadialPaletteView: View {
    @ObservedObject var model: PaletteModel
    let onAction: (PaletteAction) -> Void
    let onDismiss: () -> Void

    @State private var hoveredIndex: Int? = nil
    @State private var appearanceScale: CGFloat = 0.5
    @State private var appearanceOpacity: Double = 0.0

    private var items: [RadialPaletteActionItem] {
        let hasToken = AutoSanitizerService.shared.hasDetectedTokenInClipboard
        return [
            RadialPaletteActionItem(
                title: "Nettoyer",
                subtitle: "Secrets & ⌘V",
                icon: "sparkles",
                gradient: [Color.pink, Color(red: 1.0, green: 0.35, blue: 0.65)],
                action: .pasteCleaned
            ),
            RadialPaletteActionItem(
                title: "Bonsai IA",
                subtitle: "Correction 4B",
                icon: "cpu.fill",
                gradient: [Color.purple, Color.indigo],
                action: .runTransformation(.correction)
            ),
            RadialPaletteActionItem(
                title: "Tableau",
                subtitle: "Markdown / CSV",
                icon: "tablecells.fill",
                gradient: [Color.blue, Color.cyan],
                action: .runTransformation(.convertTable)
            ),
            RadialPaletteActionItem(
                title: hasToken ? "Coller Token" : "Coller Brut",
                subtitle: hasToken ? "En clair" : "Original ⌘V",
                icon: hasToken ? "key.fill" : "doc.on.clipboard.fill",
                gradient: hasToken ? [Color.yellow, Color.orange] : [Color(white: 0.5), Color(white: 0.3)],
                action: .pasteOriginal
            ),
            RadialPaletteActionItem(
                title: "Anonymiser",
                subtitle: "Share-Ready",
                icon: "lock.shield.fill",
                gradient: [Color.teal, Color.mint],
                action: .runTransformation(.shareReady)
            ),
            RadialPaletteActionItem(
                title: "Masquer",
                subtitle: "Redact Secrets",
                icon: "eye.slash.fill",
                gradient: [Color.orange, Color.red],
                action: .runTransformation(.secretScrub)
            )
        ]
    }

    private let wheelRadius: CGFloat = 125

    var body: some View {
        ZStack {
            // Ambient Glow Backing
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.pink.opacity(0.25),
                            Color.cyan.opacity(0.15),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 180
                    )
                )
                .frame(width: 380, height: 380)

            // Glassmorphic Base Disc
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 320, height: 320)
                .overlay(
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.pink.opacity(0.6), .cyan.opacity(0.6), .purple.opacity(0.6), .pink.opacity(0.6)],
                                center: .center
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)

            // Inner orbital track
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .frame(width: 250, height: 250)

            // Action Pods (Orbital Glass Bubbles)
            ForEach(0..<items.count, id: \.self) { index in
                let angle = angleForIndex(index)
                let x = wheelRadius * cos(angle)
                let y = wheelRadius * sin(angle)
                let item = items[index]
                let isHovered = hoveredIndex == index

                Button {
                    onAction(item.action)
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: isHovered ? item.gradient : [Color.black.opacity(0.5), Color.black.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: isHovered ? [.white, item.gradient.first ?? .white] : [Color.white.opacity(0.2), Color.white.opacity(0.05)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: isHovered ? 2 : 1
                                        )
                                )
                                .shadow(color: isHovered ? (item.gradient.first ?? .pink).opacity(0.6) : .clear, radius: 10)

                            Image(systemName: item.icon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(isHovered ? .white : (item.gradient.first ?? .white))
                        }

                        Text(item.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(item.subtitle)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 76, height: 80)
                    .contentShape(Rectangle())
                    .scaleEffect(isHovered ? 1.18 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isHovered)
                }
                .buttonStyle(.plain)
                .position(x: 160 + x, y: 160 + y)
                .onHover { inside in
                    hoveredIndex = inside ? index : (hoveredIndex == index ? nil : hoveredIndex)
                }
            }

            // Center Holographic Core
            Button {
                onDismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                        .frame(width: 90, height: 90)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.pink.opacity(0.8), .cyan.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .pink.opacity(0.35), radius: 12)

                    VStack(spacing: 2) {
                        if AutoSanitizerService.shared.hasDetectedTokenInClipboard {
                            Image(systemName: "key.horizontal.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Color.yellow)

                            Text("JETON")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(Color.yellow)

                            Text("En clair")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            let text = NSPasteboard.general.string(forType: .string) ?? ""
                            let prediction = IntentProbabilityEngine.shared.predict(for: text)

                            Text(prediction.percentageString)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(prediction.probability > 0.85 ? Color.green : Color.pink)

                            Text(prediction.category.rawValue)
                                .font(.system(size: 7, weight: .bold))
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 4)

                            Text("⌃X")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Color.cyan)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 360, height: 360)
        .scaleEffect(appearanceScale)
        .opacity(appearanceOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                appearanceScale = 1.0
                appearanceOpacity = 1.0
            }
        }
    }

    private func angleForIndex(_ index: Int) -> CGFloat {
        let total = CGFloat(items.count)
        return (CGFloat(index) / total) * 2 * .pi - (.pi / 2)
    }
}
