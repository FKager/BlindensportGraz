import SwiftUI

extension Binding where Value == Bool {
    /// True while `value` holds something; setting it to false clears
    /// `value`. For alerts and dialogs driven by an optional:
    /// `.alert("Fehler", isPresented: Binding(isPresent: $errorMessage))`.
    init<Wrapped>(isPresent value: Binding<Wrapped?>) {
        self.init(
            get: { value.wrappedValue != nil },
            set: { isPresented in
                if !isPresented { value.wrappedValue = nil }
            }
        )
    }
}
