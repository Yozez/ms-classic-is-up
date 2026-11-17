import AppKit
import MSClassicCore
import SwiftUI

/// Dev tool: `MSClassicTray --snapshot <dir>` renders the real popover view with live data
/// under a mock menu bar strip, offscreen (no Screen Recording permission needed), and writes
/// `screenshot-light.png` and `screenshot-dark.png` at 2x.
enum Snapshot {
    @MainActor
    static func run(outputDirectory: String) -> Int32 {
        _ = NSApplication.shared
        let store = StatusStore()

        let clock = AppClock.fromEnvironment()
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<[MaintenanceNotice], Error> = .success([])
        Task.detached {
            do { result = .success(try await NexonClient().fetchClassicMaintenance(now: clock.now)) }
            catch { result = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        switch result {
        case .success(let notices): store.apply(notices)
        case .failure(let error):
            print("error: \(error.localizedDescription)")
            return 2
        }

        let dir = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        for state in [ServerState.up, .maintenance, .overrunning, .unknown] {
            let url = dir.appending(path: "leaf-\(state.rawValue).png")
            do {
                try leafPNG(for: state, pixels: 64).write(to: url)
                print("wrote \(url.path)")
            } catch {
                print("error: \(error.localizedDescription)")
                return 2
            }
        }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let url = dir.appending(path: "screenshot-\(name).png")
            do {
                try render(SnapshotScene(store: store, now: clock.now), appearance: appearance).write(to: url)
                print("wrote \(url.path)")
            } catch {
                print("error: \(error.localizedDescription)")
                return 2
            }
        }
        return 0
    }

    private static func leafPNG(for state: ServerState, pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        StatusIcon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels).insetBy(dx: 2, dy: 2),
                        color: StatusIcon.color(for: state))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    @MainActor
    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, scale: CGFloat = 2) throws -> Data {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}

/// A mock menu bar with the real status label, and the real popover content below it.
private struct SnapshotScene: View {
    let store: StatusStore
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 16) {
                Spacer()
                MenuBarLabelContent(store: store, showCountdown: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text(now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(.background.opacity(0.75))

            MenuContentView(store: store)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                .padding(.trailing, 150)
                .padding(.bottom, 28)
        }
        .frame(width: 620)
        .background(
            LinearGradient(colors: colorScheme == .dark
                           ? [Color(red: 0.10, green: 0.16, blue: 0.30), Color(red: 0.20, green: 0.12, blue: 0.10)]
                           : [Color(red: 0.55, green: 0.78, blue: 0.98), Color(red: 0.98, green: 0.80, blue: 0.55)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}
