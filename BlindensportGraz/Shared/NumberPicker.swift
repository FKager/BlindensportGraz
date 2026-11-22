import SwiftUI

/// Picks a number from a list (a menu), instead of a Stepper: the Stepper's
/// −/+ buttons don't grow with the text size (accessibility audit), and a
/// list is one double tap and a choice with VoiceOver.
struct NumberPicker: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let values: [Int]
    /// How a value is shown, e.g. `{ "\($0) min" }`; plain digits by default (no "2.026").
    var text: (Int) -> String = { String($0) }

    init(_ title: LocalizedStringKey, value: Binding<Int>, values: [Int], text: @escaping (Int) -> String = { String($0) }) {
        self.title = title
        self._value = value
        // The current value is always selectable, even outside the list.
        self.values = values.contains(value.wrappedValue) ? values : (values + [value.wrappedValue]).sorted()
        self.text = text
    }

    var body: some View {
        Picker(title, selection: $value) {
            ForEach(values, id: \.self) { number in
                Text(verbatim: text(number)).tag(number)
            }
        }
    }
}
