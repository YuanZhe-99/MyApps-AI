// Purpose: FluidAudio's Parakeet ASR on the Neural Engine, as plain C
// functions the app's Dart side binds (see `lasr_apple.h`).
// Inputs: A staged model folder; 16 kHz mono float samples.
// Returns: A handle per loaded model; a JSON result per transcription.
// Side effects: Loads Core ML models; runs inference.
// Notes: Every function blocks the calling thread, which is the app's worker
// isolate, never the main thread: FluidAudio's API is async, so each call
// waits on a semaphore for a detached task. The models come only from the
// folder the app's artifact manager staged — FluidAudio's own downloader is
// switched off (`ModelHub.offlineMode`), so nothing is fetched outside the
// package manifest (decision D17).

import AVFoundation
import Foundation
import FluidAudio
import Speech

/// The bridge's own version: FluidAudio's, and this file's revision.
private let bridgeVersion = strdup("fluidaudio 0.17.4 lasr-apple 2")!

/// Loaded models, by handle.
private final class Sessions: @unchecked Sendable {
    private let lock = NSLock()
    private var managers: [Int64: AsrManager] = [:]
    private var next: Int64 = 1

    func add(_ manager: AsrManager) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = next
        next += 1
        managers[id] = manager
        return id
    }

    func get(_ id: Int64) -> AsrManager? {
        lock.lock()
        defer { lock.unlock() }
        return managers[id]
    }

    func remove(_ id: Int64) -> AsrManager? {
        lock.lock()
        defer { lock.unlock() }
        return managers.removeValue(forKey: id)
    }
}

private let sessions = Sessions()

/// Purpose: Run async work to completion on the calling thread.
/// Notes: The caller is never the main thread, so waiting cannot deadlock the
/// UI; the work runs on a detached task.
private func blocking<T>(_ body: @escaping @Sendable () async throws -> T) -> Result<T, Error> {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error> = .failure(CancellationError())
    Task.detached {
        do {
            result = .success(try await body())
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

/// Purpose: Encode a value as a C string the caller frees with
/// `lasr_apple_free`.
private func json(_ object: [String: Any]) -> UnsafeMutablePointer<CChar>? {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let text = String(data: data, encoding: .utf8) else { return nil }
    return strdup(text)
}

/// Purpose: The bridge's version string.
@_cdecl("lasr_apple_version")
public func lasrAppleVersion() -> UnsafePointer<CChar> {
    UnsafePointer(bridgeVersion)
}

/// Purpose: Load a Parakeet v3 Core ML package from a staged folder.
/// Inputs: The folder holding the four `.mlmodelc` bundles and
/// `parakeet_vocab.json`; whether to keep to the CPU (for a fallback).
/// Returns: A handle above zero, or zero when the models do not load.
@_cdecl("lasr_apple_load")
public func lasrAppleLoad(_ folder: UnsafePointer<CChar>, _ cpuOnly: Int32) -> Int64 {
    ModelHub.offlineMode = true
    let url = URL(fileURLWithPath: String(cString: folder), isDirectory: true)
    let result = blocking { () async throws -> AsrManager in
        let configuration = AsrModels.defaultConfiguration()
        if cpuOnly != 0 {
            configuration.computeUnits = .cpuOnly
        }
        let models = try await AsrModels.load(from: url, configuration: configuration, version: .v3)
        let manager = AsrManager()
        try await manager.loadModels(models)
        return manager
    }
    switch result {
    case .success(let manager):
        return sessions.add(manager)
    case .failure:
        return 0
    }
}

/// Purpose: Transcribe samples with a loaded model.
/// Inputs: The handle; 16 kHz mono samples and their count.
/// Returns: JSON — `{"text": …, "tokens": [{"t": piece, "s": start, "e": end}]}`
/// or `{"error": …}` — to be freed with `lasr_apple_free`.
@_cdecl("lasr_apple_transcribe")
public func lasrAppleTranscribe(
    _ handle: Int64,
    _ samples: UnsafePointer<Float>,
    _ count: Int32
) -> UnsafeMutablePointer<CChar>? {
    guard let manager = sessions.get(handle) else {
        return json(["error": "No model is loaded for this handle."])
    }
    let audio = Array(UnsafeBufferPointer(start: samples, count: Int(count)))
    // A fresh decoder state per window: the app's windows are independent,
    // and their overlap is joined on the Dart side.
    let result = blocking { () async throws -> ASRResult in
        var state = try TdtDecoderState()
        return try await manager.transcribe(audio, decoderState: &state)
    }
    switch result {
    case .success(let asr):
        let tokens: [[String: Any]] = (asr.tokenTimings ?? []).map {
            ["t": $0.token, "s": $0.startTime, "e": $0.endTime]
        }
        return json(["text": asr.text, "tokens": tokens])
    case .failure(let error):
        return json(["error": "\(error)"])
    }
}

/// Purpose: Free a string the bridge returned.
@_cdecl("lasr_apple_free")
public func lasrAppleFree(_ text: UnsafeMutablePointer<CChar>?) {
    free(text)
}

/// Purpose: Release a loaded model.
@_cdecl("lasr_apple_release")
public func lasrAppleRelease(_ handle: Int64) {
    if let manager = sessions.remove(handle) {
        _ = blocking { await manager.cleanup() }
    }
}

// MARK: - The operating system's recogniser (L6)

/// Purpose: The on-device recogniser for a language, or nil.
/// Notes: An empty code means the device's own language. Only a recogniser
/// that can run on the device is returned: the app never sends audio to
/// Apple's servers.
private func onDeviceRecognizer(_ code: String) -> SFSpeechRecognizer? {
    var candidates: [SFSpeechRecognizer?] = []
    if code.isEmpty {
        candidates.append(SFSpeechRecognizer())
    } else {
        candidates.append(SFSpeechRecognizer(locale: Locale(identifier: code)))
        let matching = SFSpeechRecognizer.supportedLocales()
            .filter { $0.language.languageCode?.identifier == code }
            .sorted { $0.identifier < $1.identifier }
        candidates.append(contentsOf: matching.map { SFSpeechRecognizer(locale: $0) })
    }
    for case let recognizer? in candidates where recognizer.supportsOnDeviceRecognition {
        // Results on a queue of its own: the caller is blocked waiting.
        recognizer.queue = OperationQueue()
        return recognizer
    }
    return nil
}

/// Purpose: Say whether the on-device recogniser can run here.
/// Returns: 1 when the device's own language has an on-device recogniser.
@_cdecl("lasr_apple_speech_available")
public func lasrAppleSpeechAvailable() -> Int32 {
    onDeviceRecognizer("") != nil ? 1 : 0
}

/// Purpose: Transcribe samples with the operating system's on-device
/// recogniser.
/// Inputs: 16 kHz mono samples, their count, and a language code (empty for
/// the device's own).
/// Returns: JSON as `lasr_apple_transcribe` returns it, word times as
/// tokens; `{"error"}` when permission is denied or no on-device recogniser
/// exists for the language. Free with `lasr_apple_free`.
/// Notes: Asks for speech-recognition permission the first time, which is
/// only when the user chose this fallback.
@_cdecl("lasr_apple_speech_transcribe")
public func lasrAppleSpeechTranscribe(
    _ samples: UnsafePointer<Float>,
    _ count: Int32,
    _ language: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    nonisolated(unsafe) var status = SFSpeechRecognizer.authorizationStatus()
    if status == .notDetermined {
        let asked = DispatchSemaphore(value: 0)
        SFSpeechRecognizer.requestAuthorization { answer in
            status = answer
            asked.signal()
        }
        asked.wait()
    }
    guard status == .authorized else {
        return json(["error": "Speech recognition is not allowed for this app."])
    }
    let code = language.map { String(cString: $0) } ?? ""
    guard let recognizer = onDeviceRecognizer(code) else {
        return json(["error": "No on-device recogniser for '\(code)'."])
    }
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
          let channel = buffer.floatChannelData?[0] else {
        return json(["error": "Could not hold the samples."])
    }
    buffer.frameLength = AVAudioFrameCount(count)
    channel.update(from: samples, count: Int(count))

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    request.append(buffer)
    request.endAudio()

    let finished = DispatchSemaphore(value: 0)
    let lock = NSLock()
    nonisolated(unsafe) var output: [String: Any]? = nil
    let task = recognizer.recognitionTask(with: request) { result, error in
        lock.lock()
        defer { lock.unlock() }
        guard output == nil else { return }
        if let result, result.isFinal {
            output = [
                "text": result.bestTranscription.formattedString,
                "tokens": result.bestTranscription.segments.map {
                    ["t": "\u{2581}" + $0.substring, "s": $0.timestamp, "e": $0.timestamp + $0.duration]
                },
            ]
            finished.signal()
        } else if let error {
            output = ["error": "\(error.localizedDescription)"]
            finished.signal()
        }
    }
    finished.wait()
    task.cancel()
    return json(output ?? ["error": "No result."])
}
