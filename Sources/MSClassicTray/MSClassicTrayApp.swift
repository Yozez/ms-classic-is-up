import SwiftUI

@main
struct MSClassicTrayApp: App {
    @State private var store = StatusStore()
    @AppStorage("showCountdown") private var showCountdown = true

    init() {
        let args = CommandLine.arguments
        if args.contains("--status") {
            exit(StatusCLI.run())
        }
        if let i = args.firstIndex(of: "--snapshot") {
            let dir = args.indices.contains(i + 1) ? args[i + 1] : "."
            exit(MainActor.assumeIsolated { Snapshot.run(outputDirectory: dir) })
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store, showCountdown: showCountdown)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let store: StatusStore
    let showCountdown: Bool

    var body: some View {
        MenuBarLabelContent(store: store, showCountdown: showCountdown)
            .task { store.start() }
    }
}

struct MenuBarLabelContent: View {
    let store: StatusStore
    let showCountdown: Bool

    var body: some View {
        let text = showCountdown ? store.menuBarCountdown : nil
        HStack(spacing: 4) {
            Image(nsImage: StatusIcon.image(for: store.snapshot.state))
            if let text {
                Text(text).monospacedDigit()
            }
        }
    }
}
