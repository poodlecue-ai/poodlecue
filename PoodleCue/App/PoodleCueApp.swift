import SwiftUI

@main
struct PoodleCueApp: App {
    var body: some Scene {
        WindowGroup {
            PoodleCueRootView()
        }
    }
}

struct PoodleCueRootView: View {
    @StateObject private var model = LatencyTestViewModel()

    var body: some View {
        TabView {
            ConversationView(model: model)
                .tabItem {
                    Label("Conversation", systemImage: "earbuds")
                }

            LatencyTestView(model: model)
                .tabItem {
                    Label("Diagnostics", systemImage: "waveform.path.ecg")
                }
        }
    }
}

