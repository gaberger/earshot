// The driven adapters for CallAudioTap (ADR-2611240900, ADR-2611241100): a Core Audio process tap for all system
// audio (macOS 14.2+, needs only "System Audio Recording Only", never Screen Recording), and a second capture
// session for an input device (needs no permission beyond the microphone's). Audio is held in memory and handed
// back as one AudioSignal at stop; nothing is written to disk here.
import AppKit
import AVFoundation
import CoreAudio
import Foundation

/// Level in dB of a block of samples (RMS), -160 for silence.
func callAudioLevel(_ samples: UnsafeBufferPointer<Float>) -> Float {
    guard !samples.isEmpty else { return -160 }
    var sum: Float = 0
    for v in samples { sum += v * v }
    let rms = (sum / Float(samples.count)).squareRoot()
    return rms > 1e-8 ? 20 * log10(rms) : -160
}

final class CoreAudioTap: CallAudioTap, @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastLevel: Float?
    private let queue = DispatchQueue(label: "earshot.call-audio-tap")

    static var isSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0))
    }

    var level: Float? { lock.lock(); defer { lock.unlock() }; return lastLevel }

    func start(_ plan: TapPlan) throws {
        guard plan == .allSystem else { return }
        guard Self.isSupported, #available(macOS 14.2, *) else { throw AppError(message: "Call audio needs macOS 14.2 or later.") }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else {
            throw AppError(message: "Call audio could not be started. Check System Settings → Privacy & Security.")
        }
        tapID = tap
        do { try buildAggregate(tapUID: description.uuid.uuidString); try startIO() }
        catch { teardown(); throw error }
    }

    private func buildAggregate(tapUID: String) throws {
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Earshot call audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregateID) == noErr else {
            throw AppError(message: "Call audio could not be started.")
        }
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else {
            throw AppError(message: "Call audio could not be started.")
        }
    }

    private func startIO() throws {
        let channels = Int(max(1, format.mChannelsPerFrame))
        lock.lock(); lastLevel = -160; lock.unlock()
        guard AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, { [weak self] _, input, _, _, _ in
            guard let self else { return }
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            for b in buffers where b.mData != nil && b.mDataByteSize > 0 {
                let count = Int(b.mDataByteSize) / MemoryLayout<Float>.size
                let chunk = UnsafeBufferPointer(start: b.mData!.assumingMemoryBound(to: Float.self), count: count)
                if Int(b.mNumberChannels) == channels || buffers.count == 1 {
                    let l = callAudioLevel(chunk)
                    self.lock.lock(); self.samples += chunk; self.lastLevel = l; self.lock.unlock()
                }
            }
        }) == noErr, let procID, AudioDeviceStart(aggregateID, procID) == noErr else {
            throw AppError(message: "Call audio could not be started.")
        }
    }

    func stop() { teardown() }

    func finish() -> AudioSignal {
        teardown()
        lock.lock(); defer { lock.unlock() }
        let signal = AudioSignal(samples: samples, sampleRate: format.mSampleRate > 0 ? format.mSampleRate : 48_000,
                                 channels: Int(max(1, format.mChannelsPerFrame)))
        samples = []
        return signal
    }

    private func teardown() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = AudioObjectID(kAudioObjectUnknown) }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID); tapID = AudioObjectID(kAudioObjectUnknown) }
        lock.lock(); lastLevel = nil; lock.unlock()
    }
}

/// An audio input device (a virtual one such as BlackHole or Loopback, or any other) captured beside the microphone.
final class InputDeviceTap: NSObject, CallAudioTap, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "earshot.call-audio-device")
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastLevel: Float?
    private var running = false

    var level: Float? { lock.lock(); defer { lock.unlock() }; return running ? lastLevel : nil }

    func start(_ plan: TapPlan) throws {
        guard case .device(let id) = plan else { return }
        guard let device = AVCaptureDevice(uniqueID: id) else { throw AppError(message: "That input device is not connected.") }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration(); throw AppError(message: "\(device.localizedName) can't be used for call audio.")
        }
        session.addInput(input); session.addOutput(output)
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: CallAudioMix.outputRate,
                                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
        lock.lock(); lastLevel = -160; running = true; lock.unlock()
        queue.async { [session] in session.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer),
              CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer else { return }
        let chunk = UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self),
                                        count: length / MemoryLayout<Float>.size)
        let l = callAudioLevel(chunk)
        lock.lock(); samples += chunk; lastLevel = l; lock.unlock()
    }

    func stop() {
        output.setSampleBufferDelegate(nil, queue: nil)
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
        lock.lock(); running = false; lastLevel = nil; lock.unlock()
    }

    func finish() -> AudioSignal {
        stop()
        lock.lock(); defer { lock.unlock() }
        let signal = AudioSignal(samples: samples, sampleRate: CallAudioMix.outputRate, channels: 1)
        samples = []
        return signal
    }
}

/// Mixes the tap's signal into the finished microphone WAV, in place (16 kHz mono, 16-bit), so one file results.
enum CallAudioWav {
    static func merge(_ tap: AudioSignal, into url: URL) throws {
        guard !tap.samples.isEmpty else { return }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: max(frames, 1)) else { return }
        try file.read(into: buffer)
        let mic = AudioSignal(samples: Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))),
                              sampleRate: file.processingFormat.sampleRate, channels: 1)
        let mixed = CallAudioMix.mix(mic: mic, tap: tap)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: CallAudioMix.outputRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".mixing-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            let out = try AVAudioFile(forWriting: tmp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let ob = AVAudioPCMBuffer(pcmFormat: out.processingFormat, frameCapacity: AVAudioFrameCount(mixed.count)) else { return }
            ob.frameLength = AVAudioFrameCount(mixed.count)
            mixed.withUnsafeBufferPointer { ob.floatChannelData![0].update(from: $0.baseAddress!, count: mixed.count) }
            try out.write(from: ob)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

/// Where the choice and the remembered permission state live. "" = None, "all", or "app:<bundle id>".
enum CallAudioPrefs {
    static let source = "callAudioSource"
    private static let permissionKey = "callAudioPermission"
    static var permission: CallAudioPermission {
        get { switch UserDefaults.standard.string(forKey: permissionKey) { case "granted": .granted; case "refused": .refused; default: .notAsked } }
        set { UserDefaults.standard.set("\(newValue)", forKey: permissionKey) }
    }
}
