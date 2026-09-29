import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A DatePicker that can represent "no date set" via a toggle — SwiftUI's
/// DatePicker has no built-in nil state, and `birthDate`/
/// `lastMedicalExamination` are optional since much of the club's real
/// roster data omits them (see Member's doc comment in Models.swift).
struct OptionalDatePicker: View {
    let label: String
    @Binding var date: Date?

    var body: some View {
        Toggle(label, isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? (date ?? Date()) : nil }
        ))
        if date != nil {
            DatePicker(label, selection: Binding(
                get: { date ?? Date() },
                set: { date = $0 }
            ), displayedComponents: .date)
            .labelsHidden()
        }
    }
}
