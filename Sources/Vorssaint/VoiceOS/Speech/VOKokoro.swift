// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Kokoro, the assistant's natural voice: an 82-million-parameter neural
/// voice that sherpa-onnx runs on this Mac, in a small Python helper that
/// loads the model once and renders a sentence at a time to a WAV file.
/// `Tools/install-kokoro.sh` puts the helper's environment and the model in
/// the app's support folder; without them the system voices speak. The
/// helper ends when its input closes, so it never outlives the app, and it
/// stops after ten idle minutes.
@MainActor
final class VOKokoro {
    static let shared = VOKokoro()

    static let directory = VOStorage.directory.appendingPathComponent("kokoro", isDirectory: true)
    static let modelDirectory = directory.appendingPathComponent("kokoro-int8-multi-lang-v1_0", isDirectory: true)
    static let python = directory.appendingPathComponent("venv/bin/python3")

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: python.path)
            && FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent("model.int8.onnx").path)
    }

    private var process: Process?
    private var input: FileHandle?
    private var accent: String?
    private var buffer = Data()
    private var lines: [String] = []
    private var waiting: [UUID: CheckedContinuation<String?, Never>] = [:]
    private var order: [UUID] = []
    private var tail: Task<Void, Never>?
    private var idle: DispatchWorkItem?
    private static let idleAfter: TimeInterval = 600

    private init() {}

    /// Loads the model ahead of the first sentence, in the background.
    func warmUp(accent: String) {
        guard Self.isInstalled else { return }
        queue { try await self.ensureRunning(accent: accent) }
    }

    /// `text` in voice `sid` (Kokoro v1.0's numbering) at `speed`, as a WAV
    /// file the caller plays and deletes. One sentence at a time, in order.
    func render(_ text: String, sid: Int, accent: String, speed: Double) async throws -> URL {
        try await serialized {
            try await self.ensureRunning(accent: accent)
            let out = VOCLIRunner.scratchDirectory().appendingPathComponent("voice-\(UUID().uuidString).wav")
            let request: [String: Any] = ["text": text, "sid": sid, "speed": speed, "out": out.path]
            var line = try JSONSerialization.data(withJSONObject: request)
            line.append(0x0A)
            try self.input?.write(contentsOf: line)
            guard let answer = await self.nextLine(timeout: 60),
                  let json = try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any] else {
                self.stop()
                throw VOError("Kokoro didn't answer.")
            }
            guard json["ok"] as? Bool == true else { throw VOError(json["error"] as? String ?? "Kokoro couldn't speak that.") }
            self.scheduleIdleStop()
            return out
        }
    }

    func stop() {
        idle?.cancel()
        try? input?.close()
        input = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        accent = nil
        lines.removeAll()
        buffer.removeAll()
        for id in order { waiting.removeValue(forKey: id)?.resume(returning: nil) }
        order.removeAll()
    }

    // MARK: The helper

    /// Runs `work` after everything asked of the helper before it.
    private func serialized<T>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task { @MainActor () -> Result<T, Error> in
            await previous?.value
            do { return .success(try await work()) } catch { return .failure(error) }
        }
        tail = Task { _ = await task.value }
        return try await task.value.get()
    }

    /// The same, for work nobody waits on.
    private func queue(_ work: @escaping @MainActor () async throws -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            try? await work()
        }
    }

    private func ensureRunning(accent wanted: String) async throws {
        if let process, process.isRunning, accent == wanted { return }
        stop()
        guard Self.isInstalled else { throw VOError("Kokoro isn't installed.") }
        let script = Self.directory.appendingPathComponent("kokoro_voice.py")
        if (try? String(contentsOf: script, encoding: .utf8)) != Self.helper {
            try Self.helper.write(to: script, atomically: true, encoding: .utf8)
        }
        let process = Process()
        process.executableURL = Self.python
        process.arguments = ["-u", script.path, "--model-dir", Self.modelDirectory.path, "--accent", wanted,
                             // Two render as fast as four here, and leave the rest to the assistant's model.
                             "--threads", "2"]
        process.environment = VOCLIRunner.cleanEnvironment
        let stdin = Pipe(), stdout = Pipe()
        // A write after the helper ended is an error, never a SIGPIPE that ends the app.
        guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw VOError("Kokoro couldn't start.")
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.received(data) }
        }
        process.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.process === ended else { return }
                self.stop()
            }
        }
        try process.run()
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.accent = wanted
        // Loading takes a few seconds on this Mac's processor.
        guard let ready = await nextLine(timeout: 60), ready.contains("ready") else {
            stop()
            throw VOError("Kokoro didn't start.")
        }
        scheduleIdleStop()
    }

    private func received(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let first = order.first, let waiter = waiting.removeValue(forKey: first) {
                order.removeFirst()
                waiter.resume(returning: line)
            } else {
                lines.append(line)
            }
        }
    }

    private func nextLine(timeout: TimeInterval) async -> String? {
        if !lines.isEmpty { return lines.removeFirst() }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiting[id] = continuation
            order.append(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let waiter = self.waiting.removeValue(forKey: id) else { return }
                self.order.removeAll { $0 == id }
                waiter.resume(returning: nil)
            }
        }
    }

    private func scheduleIdleStop() {
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleAfter, execute: work)
    }

    /// The helper, written beside its environment whenever it changes.
    static let helper = #"""
    """Kokoro for Vorssaint + VoiceOS: loads the model once, then renders each
    line of JSON on stdin ({"text", "sid", "speed", "out"}) to a 16-bit WAV at
    "out" and answers with a line of JSON ({"ok", "seconds"} or {"ok", "error"}).
    It ends when stdin closes, which the app's quitting does too."""
    import argparse, array, json, sys, wave

    import sherpa_onnx


    def main():
        parser = argparse.ArgumentParser()
        parser.add_argument("--model-dir", required=True)
        parser.add_argument("--accent", choices=["us", "gb"], default="us")
        parser.add_argument("--threads", type=int, default=4)
        args = parser.parse_args()
        d = args.model_dir
        kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(
            model=f"{d}/model.int8.onnx", voices=f"{d}/voices.bin", tokens=f"{d}/tokens.txt",
            data_dir=f"{d}/espeak-ng-data", dict_dir=f"{d}/dict",
            lexicon=f"{d}/lexicon-{args.accent}-en.txt,{d}/lexicon-zh.txt")
        config = sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(kokoro=kokoro, num_threads=args.threads, provider="cpu"),
            max_num_sentences=1)
        tts = sherpa_onnx.OfflineTts(config)
        print(json.dumps({"ready": True}), flush=True)
        for line in sys.stdin:
            try:
                request = json.loads(line)
                audio = tts.generate(request["text"], sid=int(request.get("sid", 0)),
                                     speed=float(request.get("speed", 1.0)))
                pcm = array.array("h", (int(max(-1.0, min(1.0, s)) * 32767) for s in audio.samples))
                with wave.open(request["out"], "wb") as out:
                    out.setnchannels(1)
                    out.setsampwidth(2)
                    out.setframerate(audio.sample_rate)
                    out.writeframes(pcm.tobytes())
                print(json.dumps({"ok": True, "seconds": len(audio.samples) / audio.sample_rate}), flush=True)
            except Exception as error:  # one bad line answers with its error, and the next goes on
                print(json.dumps({"ok": False, "error": str(error)}), flush=True)


    if __name__ == "__main__":
        main()

    """#
}
