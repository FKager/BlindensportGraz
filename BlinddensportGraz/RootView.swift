import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext

    init() {
        // Empty initializer - models already initialized in App struct
    }

    var body: some View {
        NavigationStack {
            MainTabView()
                .environmentObject(modelContext)
        }
    }
}
