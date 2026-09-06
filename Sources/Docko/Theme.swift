import AppKit
import SwiftUI

/// Vocabulaire visuel partagé : surfaces calmes, bordures fines, coins doux, accent discret.
/// Toutes les couleurs dérivent des couleurs système pour suivre le mode clair/sombre.
enum Theme {
    static let radius: CGFloat = 10
    static let radiusSmall: CGFloat = 7

    static var canvas: Color { Color(nsColor: .windowBackgroundColor) }
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var surfaceRaised: Color { Color(nsColor: .underPageBackgroundColor) }
    static var border: Color { Color(nsColor: .separatorColor) }
    static var borderStrong: Color { Color(nsColor: .tertiaryLabelColor).opacity(0.5) }
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var radius: CGFloat = Theme.radius

    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.border)
            )
    }
}

extension View {
    /// Carte : fond de surface, bordure fine, coins continus.
    func card(radius: CGFloat = Theme.radius) -> some View {
        modifier(CardModifier(radius: radius))
    }
}

// MARK: - Typographie

/// Étiquette de section en petites capitales grises, comme un intitulé de colonne.
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Pastilles

/// Petite capsule d'état : « Appliqué », « ⌘D puis 1 »…
struct Pill: View {
    enum Style {
        case neutral
        case accent
        case success
    }

    let text: String
    var systemImage: String? = nil
    var style: Style = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .overlay(Capsule().strokeBorder(outline))
    }

    private var foreground: Color {
        switch style {
        case .neutral: return .secondary
        case .accent: return .accentColor
        case .success: return .green
        }
    }

    private var background: Color {
        switch style {
        case .neutral: return Theme.surfaceRaised
        case .accent: return Color.accentColor.opacity(0.12)
        case .success: return Color.green.opacity(0.12)
        }
    }

    private var outline: Color {
        switch style {
        case .neutral: return Theme.border
        case .accent: return Color.accentColor.opacity(0.25)
        case .success: return Color.green.opacity(0.3)
        }
    }
}

/// Pastille de couleur d'un profil : carré arrondi plutôt qu'un rond, plus posé.
struct ColorSwatch: View {
    let hex: String
    var size: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Color(hex: hex))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.black.opacity(0.12))
            )
    }
}

// MARK: - Icônes

/// Icône d'application depuis son chemin, ou un symbole de remplacement.
struct AppIconView: View {
    let item: DockItem
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch item.kind {
            case .app:
                if let path = item.path, item.existsOnDisk {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .interpolation(.high)
                } else {
                    placeholder("app.dashed")
                }
            case .spacer:
                placeholder("arrow.left.and.right")
            case .smallSpacer:
                placeholder("arrow.left.and.right")
                    .font(.system(size: size * 0.32))
            }
        }
        .frame(width: size, height: size)
    }

    private func placeholder(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(Theme.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                    .strokeBorder(Theme.border)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - États vides

struct EmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.border)
                )
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.secondary)
                )
                .frame(width: 64, height: 64)
            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
            actions
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Logotype

/// Le logotype Docko (barres du Dock + nom), en image modèle : noir sur thème clair,
/// blanc sur thème sombre, carrés en gris léger. Source : Resources/Wordmark.png,
/// généré depuis web/assets/docko-title.png (l'encre devient de l'opacité).
struct Wordmark: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "Wordmark", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(.primary)
                .accessibilityLabel("Docko")
        } else {
            Text("Docko")
                .font(.headline)
        }
    }
}
