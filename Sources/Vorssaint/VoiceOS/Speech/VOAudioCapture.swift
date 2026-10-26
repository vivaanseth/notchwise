// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Speech/AudioCapture.swift) into Vorssaint + VoiceOS.

import AVFoundation
import CoreAudio
import AudioToolbox

/// Microphone capture with level metering. Buffers are forwarded to a live recognizer and also
/// collected as 16 kHz mono floats for VOWhisper.
final class VOAudioCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var isRunning = false
    private var startedAt = Date()
    private var smoothed: Float = 0

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onLevel: ((Float) -> Void)?

    func start(deviceUID: String) throws {
        stop()
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        smoothed = 0

        let input = engine.inputNode
        if !deviceUID.isEmpty, let id = VOAudioDevices.deviceID(forUID: deviceUID), let unit = input.audioUnit {
            var dev = id
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VOError("No microphone input available.") }
        converter = AVAudioConverter(from: format, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
        startedAt = Date()
    }

    /// Stops capture and returns the 16 kHz samples plus the spoken duration.
    @discardableResult
    func stop() -> (samples: [Float], duration: Double) {
        guard isRunning else { return ([], 0) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.lock(); let s = samples; lock.unlock()
        return (s, Date().timeIntervalSince(startedAt))
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        onBuffer?(buffer)

        // Level (RMS → 0…1 with a perceptual curve).
        if let ch = buffer.floatChannelData?[0] {
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = sqrt(sum / Float(max(n, 1)))
            let db = 20 * log10(max(rms, 0.000_01))
            let level = max(0, min(1, (db + 55) / 45))
            smoothed = level > smoothed ? smoothed * 0.4 + level * 0.6 : smoothed * 0.8 + level * 0.2
            onLevel?(smoothed)
        }

        // Resample for VOWhisper.
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let data = out.floatChannelData?[0], out.frameLength > 0 {
            let chunk = Array(UnsafeBufferPointer(start: data, count: Int(out.frameLength)))
            lock.lock(); samples.append(contentsOf: chunk); lock.unlock()
        }
    }

    /// Writes 16-bit PCM WAV for whisper.cpp.
    static func writeWAV(_ samples: [Float], to url: URL) throws {
        var data = Data()
        let sampleRate: UInt32 = 16_000
        let byteCount = UInt32(samples.count * 2)
        func append<T>(_ v: T) { var v = v; data.append(Data(bytes: &v, count: MemoryLayout<T>.size)) }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount).littleEndian)
        data.append(contentsOf: Array("WAVE".utf8)); data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16).littleEndian); append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(sampleRate.littleEndian); append((sampleRate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8)); append(byteCount.littleEndian)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for (i, s) in samples.enumerated() { pcm[i] = Int16(max(-1, min(1, s)) * 32_767) }
        pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        try data.write(to: url)
    }
}

/// CoreAudio input device enumeration for the microphone picker.
enum VOAudioDevices {
    struct Device: Identifiable, Hashable { let id: String; let name: String }

    static func inputDevices() -> [Device] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannels(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(id: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids.first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }
}
