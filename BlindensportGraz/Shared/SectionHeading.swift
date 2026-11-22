import SwiftUI

/// A list or form section header in full text colour. The system's grey
/// header text reaches only about 4.3:1 on the light grouped background,
/// just under WCAG AA (4.5:1); the accessibility audit flags it.
struct SectionHeading: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            // Color.primary, not .primary: in a header .primary means the header's own grey level.
            .foregroundStyle(Color.primary)
    }
}

extension Section where Parent == SectionHeading, Content: View, Footer == EmptyView {
    /// `Section("Titel") { … }`, but with the header in full text colour
    /// (`SectionHeading`); use this instead of the plain title initializer.
    init(heading: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SectionHeading(heading) })
    }
}
