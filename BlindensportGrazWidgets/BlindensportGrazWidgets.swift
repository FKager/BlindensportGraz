import WidgetKit
import SwiftUI

/// Home-screen widget: the user's next training or tournament
/// (architecture-review.md §5). Reads a small snapshot the app writes into
/// the App Group via `WidgetBridge` — no SwiftData in the extension.

struct NextUpEntry: TimelineEntry {
    let date: Date
    let snapshot: NextUpSnapshot?
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        NextUpEntry(date: .now, snapshot: NextUpSnapshot(
            kind: .training, title: "Abendtraining",
            startDate: .now.addingTimeInterval(3600), location: "Sporthalle Eggenberg"
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(NextUpEntry(date: .now, snapshot: WidgetBridge.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let snapshot = WidgetBridge.read()
        let entry = NextUpEntry(date: .now, snapshot: snapshot)
        // Re-read at the event's start (so it rolls over to the next one, or
        // to "Kein Termin") or in an hour, whichever comes first. The app
        // also reloads the timeline directly after every sync/edit.
        let refreshAt = min(snapshot?.startDate ?? .distantFuture, Date.now.addingTimeInterval(3600))
        completion(Timeline(entries: [entry], policy: .after(refreshAt)))
    }
}

struct NextUpWidgetView: View {
    var entry: NextUpEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            filled(snapshot)
        } else {
            empty
        }
    }

    private func filled(_ snapshot: NextUpSnapshot) -> some View {
        let isTraining = snapshot.kind == .training
        let dateFormat: Date.FormatStyle = isTraining
            ? .dateTime.weekday(.abbreviated).day().month().hour().minute()
            : .dateTime.weekday(.abbreviated).day().month()
        return VStack(alignment: .leading, spacing: 4) {
            Label(isTraining ? "Nächstes Training" : "Nächstes Turnier",
                  systemImage: isTraining ? "figure.run" : "trophy.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(snapshot.title)
                .font(.headline)
                .lineLimit(family == .systemSmall ? 2 : 1)
            Text(snapshot.startDate, format: dateFormat)
                .font(.caption)
                .foregroundStyle(.secondary)
            if family != .systemSmall, !snapshot.location.isEmpty {
                Label(snapshot.location, systemImage: "mappin.and.ellipse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Kein bevorstehender Termin")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BlindensportNextUp", provider: NextUpProvider()) { entry in
            NextUpWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nächster Termin")
        .description("Dein nächstes Training oder Turnier.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BlindensportGrazWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
    }
}
