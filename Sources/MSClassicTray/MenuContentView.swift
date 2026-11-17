import MSClassicCore
import SwiftUI

struct MenuContentView: View {
    let store: StatusStore
    @AppStorage("showCountdown") private var showCountdown = true
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    private var snapshot: StatusSnapshot { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            nextMaintenance
            Divider()
            footer
            Divider()
            settings
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: StatusIcon.image(for: snapshot.state, size: 28))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("MapleStory Classic World").font(.caption).foregroundStyle(.secondary)
                Text(headline).font(.headline)
                if let detail = headlineDetail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var headline: String {
        switch snapshot.state {
        case .up: "Up"
        case .maintenance: "Down for maintenance"
        case .overrunning: "Maintenance running late"
        case .unknown: store.isRefreshing ? "Checking…" : "Status unknown"
        }
    }

    private var headlineDetail: String? {
        switch snapshot.state {
        case .up:
            return "No maintenance in progress, per Nexon notices."
        case .maintenance:
            guard let end = snapshot.current?.end else { return "Until further notice." }
            return "Expected back \(Self.time(end)) (\(StatusStore.countdown(to: end, from: store.now)))."
        case .overrunning:
            guard let end = snapshot.current?.end else { return nil }
            return "Was due back \(Self.time(end)). Nexon hasn't marked it completed yet."
        case .unknown:
            return store.lastError.map { "Couldn't reach Nexon: \($0)" }
        }
    }

    @ViewBuilder
    private var nextMaintenance: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next maintenance").font(.caption).foregroundStyle(.secondary)
            if let next = snapshot.next {
                Text(Self.range(next)).font(.body.weight(.medium))
                Text(Self.relative(next.start, now: store.now)).font(.subheadline).foregroundStyle(.secondary)
                Text(next.displayTitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else if snapshot.state == .unknown {
                Text("—").foregroundStyle(.secondary)
            } else {
                Text("None scheduled").font(.body)
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let checked = store.lastChecked {
                    Text("Checked \(checked.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("Not checked yet")
                }
                if let error = store.lastError, snapshot.state != .unknown {
                    Text("Last refresh failed: \(error)").foregroundStyle(.orange).lineLimit(2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(store.isRefreshing)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show countdown in menu bar", isOn: $showCountdown)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    loginError = LoginItem.setEnabled(newValue)
                    if loginError != nil { launchAtLogin = LoginItem.isEnabled }
                }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("Times shown in \(TimeZone.current.localizedName(for: .shortGeneric, locale: .current) ?? TimeZone.current.identifier)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: Formatting (local time zone)

    static func time(_ date: Date) -> String {
        let sameDay = Calendar.current.isDateInToday(date)
        return sameDay
            ? "at \(date.formatted(date: .omitted, time: .shortened))"
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func range(_ n: MaintenanceNotice) -> String {
        let day = n.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let start = n.start.formatted(date: .omitted, time: .shortened)
        guard let end = n.end else { return "\(day) · \(start) – ?" }
        var endText = end.formatted(date: .omitted, time: .shortened)
        if !Calendar.current.isDate(n.start, inSameDayAs: end) {
            endText += " " + end.formatted(.dateTime.weekday(.abbreviated))
        }
        return "\(day) · \(start) – \(endText)"
    }

    static func relative(_ date: Date, now: Date) -> String {
        "Starts in \(StatusStore.countdown(to: date, from: now))"
    }
}
