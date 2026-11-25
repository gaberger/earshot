// The Call audio row, inside Settings → Recording under Microphone (ADR-2611241100).
import AppKit
import AVFoundation
import SwiftUI

struct CallAudioSettingsRows: View {
    @AppStorage(CallAudioPrefs.source) private var stored = ""
    @AppStorage(MicRecorder.settingKey) private var microphoneID = ""
    @State private var inputs: [AVCaptureDevice] = []
    @State private var permission = CallAudioPrefs.permission
    @Environment(\.openURL) private var openURL

    private var defaultMicID: String? { AVCaptureDevice.default(for: .audio)?.uniqueID }
    private var options: [CallAudioOption] {
        CallAudioRules.options(inputs: inputs.map { (id: $0.uniqueID, name: $0.localizedName) }, microphoneID: microphoneID,
                               defaultMicrophoneID: defaultMicID, osSupportsTap: CoreAudioTap.isSupported)
    }
    private var source: CallAudioSource {
        CallAudioRules.effectiveSource(stored: stored, microphoneID: microphoneID, defaultMicrophoneID: defaultMicID)
    }

    var body: some View {
        Group {
            SettingsRow("Call audio",
                        detail: "Also record the other side of a call, from all system audio or from an input device such as BlackHole or Loopback. "
                            + "It can include other people's voices, so tell them, and only record where that is allowed. The audio stays on this Mac.") {
                Picker("", selection: $stored) {
                    ForEach(options, id: \.id) { Text($0.name).tag($0.id) }
                    if !stored.isEmpty, !options.contains(where: { $0.id == stored }), CallAudioSource.read(stored) != .none {
                        Text("Not available").tag(stored)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 190, alignment: .trailing)
            }
            switch CallAudioRules.cardAction(source: source, permission: permission, osSupportsTap: CoreAudioTap.isSupported) {
            case .openSettings:
                SettingsRow("System audio permission",
                            detail: "macOS did not allow Earshot to record system audio. Allow it in Privacy & Security → Screen & System Audio Recording.") {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                            openURL(url)
                        }
                    }
                }
            case .allow:
                SettingsRow("System audio permission", detail: "macOS asks the first time Earshot records with All system audio.") { EmptyView() }
            case .none:
                EmptyView()
            }
        }
        .onAppear { inputs = MicRecorder.inputs(); permission = CallAudioPrefs.permission }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in inputs = MicRecorder.inputs() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in inputs = MicRecorder.inputs() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            inputs = MicRecorder.inputs(); permission = CallAudioPrefs.permission
        }
    }
}
