import SwiftUI

/// "Drucken" for one or more report files: renders them (ReportPrinter) and
/// opens the system print dialog once for all of them. `files` is called on
/// tap, so it prints exactly what is selected at that moment.
struct ReportPrintButton: View {
    var title: LocalizedStringKey = "Drucken"
    let jobName: String
    let files: () throws -> [URL]

    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task { await printFiles() }
        } label: {
            HStack {
                Label(title, systemImage: "printer")
                if isPreparing {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(isPreparing)
        .accessibilityHint("Bereitet die Dokumente auf und öffnet den Druckdialog.")
        .alert("Drucken nicht möglich", isPresented: Binding(get: { errorMessage != nil },
                                                             set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func printFiles() async {
        isPreparing = true
        defer { isPreparing = false }
        do {
            try await ReportPrinter.print(try files(), jobName: jobName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
