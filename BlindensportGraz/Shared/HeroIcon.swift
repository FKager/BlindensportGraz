import SwiftUI

/// Large decorative symbol at the top of a screen (landing page, welcome
/// screen, import sheet). Grows with Dynamic Type instead of using a fixed
/// point size, and is hidden from VoiceOver — the heading next to it says
/// what the screen is.
struct HeroIcon: View {
    let systemName: String
    /// Point size at the default text size; scaled with the user's setting.
    var size: Double = 56
    var style: AnyShapeStyle = AnyShapeStyle(Theme.brandGradient)

    @ScaledMetric(relativeTo: .largeTitle) private var scale = 1.0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * scale))
            .foregroundStyle(style)
            .accessibilityHidden(true)
    }
}
