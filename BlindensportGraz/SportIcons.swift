import SwiftUI

/// Central place for sport-specific iconography, used anywhere a Training/
/// Tournament/Team/Event's freeform `sport` string needs a visual badge
/// (list rows, "Sportart" pickers). `sport` is user-editable free text (see
/// the TextField editors in TeamsViews/TournamentsViews/TrainingsViews), not
/// a fixed enum, so every lookup here goes through `Sport.normalize` (see
/// Sport.swift) and falls back gracefully for anything not in the known
/// list — this used to be its own private normalize+switch here; now shared
/// with anything else that needs type-safe sport handling.
enum SportIcon {

    /// SF Symbol best matching each known sport. Falls back to a generic
    /// "sportscourt.fill" for unrecognized/custom sport text.
    static func symbolName(for sport: String) -> String {
        switch Sport.normalize(sport) {
        case .torball: return "bell.fill"
        case .goalball: return "sportscourt.fill"
        case .blindenfussball: return "figure.soccer"
        case .showdown: return "figure.table.tennis"
        case .judo: return "figure.martial.arts"
        case .leichtathletik: return "figure.track.and.field"
        case .schwimmen: return "figure.pool.swim"
        case .ski: return "figure.skiing.downhill"
        case .radfahren: return "figure.outdoor.cycle"
        case .other: return "sportscourt.fill"
        }
    }

    /// Accent color paired with each sport's icon, echoing the tinted-circle
    /// style already used by StatCard/EventRow elsewhere in the app.
    static func color(for sport: String) -> Color {
        switch Sport.normalize(sport) {
        case .torball: return .orange
        case .goalball: return .green
        case .blindenfussball: return .mint
        case .showdown: return .purple
        case .judo: return .red
        case .leichtathletik: return .yellow
        case .schwimmen: return .cyan
        case .ski: return .indigo
        case .radfahren: return .pink
        case .other: return .blue
        }
    }

    /// Sports with no good SF Symbol equivalent — they're specific to
    /// blind/para sport and don't exist in Apple's system-icon set — get a
    /// small hand-drawn pictogram instead of a system glyph. See
    /// `SportPictogram`.
    static func hasCustomGlyph(for sport: String) -> Bool {
        switch Sport.normalize(sport) {
        case .torball, .goalball, .showdown: return true
        default: return false
        }
    }
}

/// A small circular badge for a sport: a hand-drawn vector pictogram for
/// sports SF Symbols has no equivalent for (Torball/Goalball/Showdown),
/// otherwise the closest matching SF Symbol on a tinted background. Purely
/// decorative — always paired with a text label announcing the sport name
/// (row title, `Label`), so it's hidden from VoiceOver rather than read out
/// as an unhelpful shape description. This app's primary users navigate by
/// VoiceOver — see cerebrum's standing VoiceOver preference notes.
struct SportGlyph: View {
    let sport: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(SportIcon.color(for: sport).opacity(0.15))
            if SportIcon.hasCustomGlyph(for: sport) {
                SportPictogram(sport: sport)
                    .stroke(
                        SportIcon.color(for: sport),
                        style: StrokeStyle(lineWidth: max(1.5, size * 0.07), lineCap: .round, lineJoin: .round)
                    )
                    .padding(size * 0.22)
            } else {
                Image(systemName: SportIcon.symbolName(for: sport))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(SportIcon.color(for: sport))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Hand-drawn pictograms for the three blind-sport-specific icons SF Symbols
/// doesn't cover, each normalized to draw within `rect` (a unit square scaled
/// to the view's actual size) — the same "normalize, then scale" approach a
/// hand-authored SVG path uses, just expressed as a native SwiftUI `Shape`
/// instead of an imported vector asset (no asset-catalog/SVG-import step
/// needed, and it's guaranteed to compile/render since it's plain code).
private struct SportPictogram: Shape {
    let sport: String

    func path(in rect: CGRect) -> Path {
        switch Sport.normalize(sport) {
        case .torball: return torball(in: rect)
        case .goalball: return goalball(in: rect)
        case .showdown: return showdown(in: rect)
        default: return Path()
        }
    }

    /// A ball (outer ring) with three small bells inside, arranged in a
    /// triangle — Torball's defining feature is the bells inside the ball
    /// that let blind players track it by sound.
    private func torball(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: rect.insetBy(dx: rect.width * 0.04, dy: rect.height * 0.04))

        let cx = rect.midX, cy = rect.midY
        let d = rect.width * 0.17
        let r = rect.width * 0.05
        let bellCenters = [
            CGPoint(x: cx, y: cy - d),
            CGPoint(x: cx - d * 0.87, y: cy + d * 0.5),
            CGPoint(x: cx + d * 0.87, y: cy + d * 0.5),
        ]
        for c in bellCenters {
            p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        return p
    }

    /// A goal frame (posts + crossbar) with the ball resting in front of
    /// it — Goalball is about rolling the ball into the opponents' goal.
    private func goalball(in rect: CGRect) -> Path {
        var p = Path()
        let left = rect.minX + rect.width * 0.14
        let right = rect.maxX - rect.width * 0.14
        let top = rect.minY + rect.height * 0.14
        let postBottom = rect.minY + rect.height * 0.56

        p.move(to: CGPoint(x: left, y: postBottom))
        p.addLine(to: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: right, y: top))
        p.addLine(to: CGPoint(x: right, y: postBottom))

        let ballR = rect.width * 0.15
        let ballCenter = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.78)
        p.addEllipse(in: CGRect(x: ballCenter.x - ballR, y: ballCenter.y - ballR, width: ballR * 2, height: ballR * 2))
        return p
    }

    /// A table with a raised center barrier and the ball beside it —
    /// Showdown is played on an enclosed table split by a center screen,
    /// tracked by sound like Torball.
    private func showdown(in rect: CGRect) -> Path {
        var p = Path()
        let table = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.24)
        p.addRoundedRect(in: table, cornerSize: CGSize(width: rect.width * 0.05, height: rect.width * 0.05))

        p.move(to: CGPoint(x: rect.midX, y: table.minY - rect.height * 0.08))
        p.addLine(to: CGPoint(x: rect.midX, y: table.maxY + rect.height * 0.08))

        let ballR = rect.width * 0.06
        let ballCenter = CGPoint(x: rect.midX - rect.width * 0.18, y: rect.midY)
        p.addEllipse(in: CGRect(x: ballCenter.x - ballR, y: ballCenter.y - ballR, width: ballR * 2, height: ballR * 2))
        return p
    }
}
