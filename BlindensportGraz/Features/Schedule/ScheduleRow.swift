import SwiftUI

/// One entry of the public schedule: name, day(s) and location only — no
/// times, participants, costs or notes.
struct ScheduleRow: View {
    let title: String
    let start: Date
    let end: Date
    let location: String

    private var isMultiDay: Bool {
        !Calendar.current.isDate(start, inSameDayAs: end) && end > start
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(.headline)
            Group {
                if isMultiDay {
                    Text("\(start.formatted(.dateTime.weekday(.abbreviated).day().month())) – \(end.formatted(.dateTime.weekday(.abbreviated).day().month().year()))")
                } else {
                    Text(start, format: .dateTime.weekday(.abbreviated).day().month().year())
                }
            }
            .font(.subheadline)
            if !location.isEmpty {
                // Icon and text in one wrapping line; a Label cut the text off at large sizes.
                Text("\(Image(systemName: "mappin.and.ellipse")) \(location)")
                    .font(.subheadline)
                    .accessibilityLabel(location)
            }
        }
        // Date and place in full text colour: the system grey is under 4.5:1 in light mode.
        .foregroundStyle(Color.primary)
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
