import AppKit
import AutoClickCore
import SwiftUI

struct ControlsView: View {
    @ObservedObject var model: AppModel
    var close: () -> Void
    @FocusState private var focusedField: String?
    @StateObject private var edits = TimingDrafts()

    private var accent: Color { model.mode == .off ? .secondary : .accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Clicker").font(.system(size: 17, weight: .semibold))
                    Text("Your pace. Your shortcut.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.mode == .off ? "OFF" : model.mode == .hold ? "HOLD" : "AUTO")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(accent)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(model.isReady ? accent : .orange).frame(width: 6, height: 6)
                    Text(model.statusTitle).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if model.mode != .off {
                        Text("PAUSED IN PANEL").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                Text(model.statusDetail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.isReady {
                    Button("Open Accessibility Settings…") { model.requestAccessibility() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Text("Enable Auto Clicker in the list. If it is missing, add it with + from your Applications folder.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 8) {
                modeButton("Hold M1", symbol: "computermouse", mode: .hold)
                modeButton("Continuous", symbol: "repeat", mode: .continuous)
                Button {
                    commitAllFields()
                    focusedField = nil
                    model.selectMode(.off)
                } label: {
                    Image(systemName: "stop.fill").frame(width: 26, height: 25)
                }
                .help("Turn off either mode (⌘ Page Down)")
                .accessibilityLabel("Stop clicking")
            }
            .buttonStyle(.bordered).controlSize(.regular)

            VStack(alignment: .leading, spacing: 10) {
                Text("CLICK TIMING").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                timingRow("Delay between clicks", id: "click", range: 10...60_000)
                HStack {
                    Text("Clicks per burst").font(.system(size: 12))
                    Spacer()
                    TextField("1", text: textBinding(for: "burst"))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                    .frame(width: 77).focused($focusedField, equals: "burst")
                    .accessibilityLabel("Clicks per burst, 1 to 1000")
                    Text("clicks").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 31, alignment: .leading)
                }
                timingRow("Pause between bursts", id: "pause", range: 0...3_600_000)
                timingRow("Delay before starting", id: "start", range: 0...3_600_000)
                Text("Hold M1: one click immediately, then the start delay. Burst pause is added after the normal click delay.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(spacing: 7) {
                shortcutRow("Hold to click", keys: "⌘ PgUp")
                shortcutRow("Continuous click", keys: "⌘ ⇧ PgUp")
                shortcutRow("Stop either mode", keys: "⌘ PgDown / ⌘ ⇧ PgDown")
                Text("MacBook: Page Up = fn ↑  ·  Page Down = fn ↓")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
            }

            if let error = model.shortcutError ?? model.message {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                Spacer()
                Button("Quit") { commitAllFields(); NSApp.terminate(nil) }.buttonStyle(.plain)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if model.loginNeedsApproval {
                Button("Approve in Login Items…") { model.openLoginSettings() }
                    .font(.system(size: 11))
            }
        }
        .padding(20)
        .frame(width: 374)
        .background(VisualEffectBackground())
        .onExitCommand { commitAllFields(); focusedField = nil; close() }
        .onSubmit { commitAllFields(); focusedField = nil }
        .onChange(of: focusedField) { field in
            if let previousField = edits.previousField, previousField != field { commitField(previousField) }
            edits.previousField = field
        }
        .onDisappear { commitAllFields() }
    }

    private func modeButton(_ title: String, symbol: String, mode: ClickMode) -> some View {
        Button {
            commitAllFields()
            focusedField = nil
            model.selectMode(mode)
            close()
        } label: {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 25)
        }
        .tint(model.mode == mode ? .accentColor : .secondary)
        .disabled(!model.isReady)
    }

    private func timingRow(_ title: String, id: String, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            TextField("0", text: textBinding(for: id))
            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
            .frame(width: 77).focused($focusedField, equals: id)
            .accessibilityLabel("\(title), milliseconds")
            .help("\(Int(range.lowerBound))–\(Int(range.upperBound)) milliseconds")
            Text("ms").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 31, alignment: .leading)
        }
    }

    private func shortcutRow(_ title: String, keys: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(keys).font(.system(size: 10, weight: .medium, design: .monospaced))
        }
    }

    private func textBinding(for id: String) -> Binding<String> {
        Binding(get: { edits.values[id] ?? formattedValue(for: id) }, set: { edits.values[id] = $0 })
    }

    private func formattedValue(for id: String) -> String {
        let value: Double
        switch id {
        case "click": value = model.configuration.clickDelayMilliseconds
        case "burst": value = Double(model.configuration.clicksPerBurst)
        case "pause": value = model.configuration.burstPauseMilliseconds
        default: value = model.configuration.startDelayMilliseconds
        }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    private func commitField(_ id: String) {
        guard let text = edits.values[id] else { return }
        let decimal = Locale.current.decimalSeparator ?? "."
        if let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: decimal, with: ".")), value.isFinite {
            model.updateConfiguration {
                switch id {
                case "click": $0.clickDelayMilliseconds = value
                case "burst": $0.clicksPerBurst = Int(min(1000, max(1, value)))
                case "pause": $0.burstPauseMilliseconds = value
                default: $0.startDelayMilliseconds = value
                }
            }
        }
        edits.values[id] = nil
    }

    private func commitAllFields() {
        for id in ["click", "burst", "pause", "start"] { commitField(id) }
    }
}

private final class TimingDrafts: ObservableObject {
    var previousField: String?
    @Published var values: [String: String] = [:]
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
