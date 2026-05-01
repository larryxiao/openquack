import SwiftUI
import AppKit

/// Design tokens + reusable SwiftUI components that give every surface a
/// consistent voice. The critique that motivated this file said it best:
/// "every design 'doesn't' traces back to no shared tokens." This file is
/// the spine.

enum Theme {
    // MARK: - Palette (light-leaning; dark mode keeps system defaults)

    /// Warm cream — used as background on "reception" surfaces (onboarding,
    /// About). Not a global app background; keep system materials elsewhere.
    static let cream       = Color(red: 0.961, green: 0.949, blue: 0.925)  // #F5F2EC
    static let creamRaised = Color(red: 0.910, green: 0.875, blue: 0.788)  // #E8DFC9
    static let ink         = Color(red: 0.169, green: 0.153, blue: 0.133)  // #2B2722

    /// Status palette. Muted, native-feeling — not the system rainbow.
    static let coral       = Color(red: 0.792, green: 0.337, blue: 0.290)  // #CA564A — recording
    static let amber       = Color(red: 0.851, green: 0.671, blue: 0.290)  // #D9AB4A — warming / transcribing
    static let moss        = Color(red: 0.349, green: 0.518, blue: 0.318)  // #59844F — idle / ready / success

    /// 1 pt card stroke — works in both light and dark mode.
    static let hairline    = Color.primary.opacity(0.08)

    // MARK: - Spacing scale

    static let s4:  CGFloat = 4
    static let s8:  CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32

    // MARK: - Corner radius scale

    /// Inline pills: status badges, small chips.
    static let rInline:   CGFloat = 8
    /// Cards: banners, transcript card, settings rows, privacy rows.
    static let rCard:     CGFloat = 12
    /// Floating chrome: overlay pill, popover edges (where exposed).
    static let rFloating: CGFloat = 16
}

// MARK: - Typography roles

extension Font {
    /// Onboarding welcome only.
    static let oqHeroSerif  = Font.system(size: 34, weight: .regular, design: .serif)
    /// Onboarding step titles, About title.
    static let oqTitleSerif = Font.system(size: 28, weight: .regular, design: .serif)
    /// Tagline italic on About.
    static let oqTaglineSerif = Font.system(size: 15, design: .serif).italic()
    /// Popover header, overlay headline, settings group titles.
    static let oqHeadline   = Font.system(size: 14, weight: .medium)
}

// MARK: - SectionHeader

/// Small-caps section label. The unifying typographic motif across every
/// surface. Use above any logical group of content.
struct SectionHeader: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

// MARK: - StatusDot

/// 8 pt circle with a 1.5 pt hairline stroke (so it holds shape on translucent
/// menu-bar materials). Colour is derived from the phase via the Theme palette.
struct StatusDot: View {
    let phase: AppState.Phase
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 1.5)
            )
    }

    private var color: Color {
        switch phase {
        case .warming:                 return Theme.amber
        case .idle, .ready:            return Theme.moss
        case .starting, .recording:    return Theme.coral
        case .transcribing:            return Theme.amber
        case .error:                   return .secondary
        }
    }
}

// MARK: - PlaceholderTextEditor

/// `TextEditor` with a `prompt` shown when empty. Encapsulates the
/// previously-duplicated "ZStack { Text if empty; TextEditor }" pattern.
struct PlaceholderTextEditor: View {
    @Binding var text: String
    let prompt: String
    var monospaced: Bool = false
    var minHeight: CGFloat = 80
    var idealHeight: CGFloat? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(prompt)
                    .foregroundStyle(.secondary)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .frame(minHeight: minHeight, idealHeight: idealHeight ?? minHeight)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rCard)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
    }
}

// MARK: - Card modifier

extension View {
    /// Standard card: subtle fill + 1 pt hairline stroke + 12 pt radius +
    /// internal padding. Used for transcript cards, banners, privacy rows.
    func oqCard(padding: CGFloat = Theme.s12) -> some View {
        self
            .padding(padding)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rCard)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
    }

    /// Soft cream card for use on cream backgrounds (onboarding privacy rows).
    /// White-over-cream gives a subtle but real lift.
    func oqCardOnCream(padding: CGFloat = Theme.s12) -> some View {
        self
            .padding(padding)
            .background(Color.white.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rCard)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
    }
}

// MARK: - Tinted banner modifier

/// Soft-fill + same-hue stroke banner. Standardises the update / accessibility
/// banner pattern in the popover so they read as objects, not glows.
extension View {
    func oqBanner(tint: Color, padding: CGFloat = Theme.s12) -> some View {
        self
            .padding(padding)
            .background(tint.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rCard)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.rCard))
    }
}

// MARK: - Cream surface background

/// Wrap a Settings pane's `Form` in cream, matching About. The form's own
/// scrolled background is hidden so cards float on the warm surface
/// instead of the default system grey.
extension View {
    func creamSettingsBackground() -> some View {
        ZStack {
            CreamSurface().ignoresSafeArea()
            self.scrollContentBackground(.hidden)
        }
    }
}

/// Drop in as the topmost layer of a "reception" surface (onboarding, About).
/// Honours dark mode by deferring to the visual-effect view there.
struct CreamSurface: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if scheme == .dark {
            VisualEffect(material: .underWindowBackground, blending: .behindWindow)
        } else {
            ZStack {
                VisualEffect(material: .underWindowBackground, blending: .behindWindow)
                    .opacity(0.4)
                Theme.cream
            }
        }
    }
}

// MARK: - Brand mark

/// Pond-blue line-art duck-in-pond mark for use on cream and neutral
/// surfaces. Source artwork: OpenQuack design system, row-5 idle variant
/// (`duck-in-pond.png` + @2x). macOS-native chrome (the menu-bar status
/// item) uses the silhouette template icons in `Resources/MenuIcons/`
/// instead — those are tiny phase glyphs, not a brand mark.
struct DuckMark: View {
    var size: CGFloat
    var body: some View {
        if let nsImage = Self.markImage {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("OpenQuack")
        } else {
            // Fallback if the resource bundle is missing — keeps layouts stable.
            Text("🦆").font(.system(size: size * 0.85))
        }
    }

    private static let markImage: NSImage? = loadBrandMark(named: "duck-in-pond")
}

/// Quacking duck — head + open beak + sound waves, pond-blue line-art.
/// Used on the menu-bar popover header where "speak / listen" reads
/// stronger than the at-rest duck-in-pond mark.
struct QuackingDuck: View {
    var size: CGFloat
    var body: some View {
        if let nsImage = Self.markImage {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel("OpenQuack")
        } else {
            Text("🦆").font(.system(size: size * 0.85))
        }
    }
    private static let markImage: NSImage? = loadBrandMark(named: "duck-quacking")
}

/// Shared bundle loader for `Resources/Brand/<name>.png` + `<name>@2x.png`.
private func loadBrandMark(named name: String) -> NSImage? {
    let bundle = Bundle.module
    guard let url1x = bundle.url(forResource: name, withExtension: "png"),
          let image = NSImage(contentsOf: url1x) else { return nil }
    let logical = image.size
    if let url2x = bundle.url(forResource: "\(name)@2x", withExtension: "png"),
       let img2x = NSImage(contentsOf: url2x),
       let rep2x = img2x.representations.first {
        rep2x.size = logical
        image.addRepresentation(rep2x)
    }
    return image
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
