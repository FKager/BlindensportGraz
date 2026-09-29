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
            .foregroundStyle(.secondary)
            if !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
