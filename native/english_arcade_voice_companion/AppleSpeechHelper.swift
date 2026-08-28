import AVFoundation
import Foundation
import Speech

// This helper accepts control-only NDJSON. It never accepts or writes audio:
// microphone samples stay in AVAudioEngine and only bounded transcript/state
// records cross the process boundary.
final class AppleSpeechHelper {
    private let maxTranscriptBytes = 12 * 1024
    private let outputLock = NSLock()
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var activeCaptureID: String?
    private var durationWorkItem: DispatchWorkItem?

    func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let command = object as? [String: Any],
              let type = command["type"] as? String else {
            emit(["type": "error", "error": "invalid_command"])
            return
        }

        switch type {
        case "start":
            let captureID = command["capture_id"] as? String ?? ""
            let language = command["language"] as? String ?? "en-US"
            start(captureID: captureID, language: language)
        case "stop", "cleanup":
            stop(emitStopped: true)
        default:
            emit(["type": "error", "error": "invalid_command"])
        }
    }

    func stop(emitStopped: Bool) {
        durationWorkItem?.cancel()
        durationWorkItem = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        recognizer = nil
        activeCaptureID = nil
        if emitStopped {
            emit(["type": "state", "state": "stopped"])
        }
    }

    private func start(captureID: String, language: String) {
        guard !captureID.isEmpty, captureID.count <= 64 else {
            emit(["type": "error", "error": "invalid_command"])
            return
        }
        stop(emitStopped: false)
        activeCaptureID = captureID
        emit(["type": "state", "state": "starting"])

        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              speechRecognizer.supportsOnDeviceRecognition else {
            fail("on_device_recognition_unavailable")
            return
        }
        recognizer = speechRecognizer

        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            guard let self else { return }
            guard authorization == .authorized else {
                self.fail("speech_permission_denied")
                return
            }
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else {
                    self.fail("microphone_permission_denied")
                    return
                }
                self.beginRecognition(speechRecognizer)
            }
        }
    }

    private func beginRecognition(_ speechRecognizer: SFSpeechRecognizer) {
        guard activeCaptureID != nil else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine = engine
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.emit(["type": "transcript", "text": self.boundedUTF8(result.bestTranscription.formattedString)])
            }
            if error != nil {
                self.fail("speech_capture_failed")
            }
        }

        do {
            engine.prepare()
            try engine.start()
            let durationWorkItem = DispatchWorkItem { [weak self] in
                self?.fail("capture_timeout")
            }
            self.durationWorkItem = durationWorkItem
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 600, execute: durationWorkItem)
            emit(["type": "state", "state": "listening"])
        } catch {
            fail("microphone_unavailable")
        }
    }

    private func fail(_ code: String) {
        stop(emitStopped: false)
        emit(["type": "error", "error": code])
    }

    private func boundedUTF8(_ text: String) -> String {
        let prefix = Data(text.utf8).prefix(maxTranscriptBytes)
        var value = String(decoding: prefix, as: UTF8.self)
        while value.utf8.count > maxTranscriptBytes {
            value.removeLast()
        }
        return value
    }

    private func emit(_ record: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record),
              data.count <= 16_384 else { return }
        outputLock.lock()
        defer { outputLock.unlock() }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}

let helper = AppleSpeechHelper()
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global(qos: .utility))
termSource.setEventHandler {
    helper.stop(emitStopped: false)
    exit(0)
}
termSource.resume()

while let line = readLine(strippingNewline: true) {
    if let data = line.data(using: .utf8) {
        helper.handle(data)
    }
}
helper.stop(emitStopped: false)
