import Foundation
import AVFoundation

// MARK: - AudioCodecDelegate

protocol AudioCodecDelegate: AnyObject {
    func audioCodec(_ codec: AudioCodec, didEncodeFrame data: Data, isKeyframe: Bool)
    func audioCodec(_ codec: AudioCodec, didDecodeFrame data: Data)
    func audioCodec(_ codec: AudioCodec, didFailWithError error: Error)
}

// MARK: - AudioCodecError

enum AudioCodecError: Error, LocalizedError {
    case encoderInitializationFailed
    case decoderInitializationFailed
    case encodingFailed
    case decodingFailed
    case invalidInputData
    case unsupportedFormat
    case codecNotAvailable

    var errorDescription: String? {
        switch self {
        case .encoderInitializationFailed: return "Failed to initialize audio encoder"
        case .decoderInitializationFailed: return "Failed to initialize audio decoder"
        case .encodingFailed: return "Audio encoding failed"
        case .decodingFailed: return "Audio decoding failed"
        case .invalidInputData: return "Invalid input data for codec"
        case .unsupportedFormat: return "Unsupported audio format"
        case .codecNotAvailable: return "Required codec is not available"
        }
    }
}

// MARK: - AudioCodecType

enum AudioCodecType: String, CaseIterable {
    case opus = "opus"
    case pcm = "pcm"

    var mimeType: String {
        switch self {
        case .opus: return "audio/opus"
        case .pcm: return "audio/pcm"
        }
    }
}

// MARK: - AudioFormat

struct AudioFormat {
    let sampleRate: Double
    let channelCount: Int
    let bitsPerChannel: Int
    let isFloat: Bool

    static let defaultFormat = AudioFormat(
        sampleRate: 48000,
        channelCount: 1,
        bitsPerChannel: 16,
        isFloat: false
    )

    static let wideband = AudioFormat(
        sampleRate: 16000,
        channelCount: 1,
        bitsPerChannel: 16,
        isFloat: false
    )

    static let narrowband = AudioFormat(
        sampleRate: 8000,
        channelCount: 1,
        bitsPerChannel: 16,
        isFloat: false
    )
}

// MARK: - OpusEncoderConfig

struct OpusEncoderConfig {
    let application: OpusApplication
    let bitrate: Int
    let frameSize: Int
    let complexity: Int
    let signalType: OpusSignalType

    enum OpusApplication: Int {
        case voip = 2048
        case audio = 2049
        case lowDelay = 2051
    }

    enum OpusSignalType: Int {
        case auto = -1000
        case voice = 3001
        case music = 3002
    }

    static let defaultConfig = OpusEncoderConfig(
        application: .voip,
        bitrate: 24000,
        frameSize: 960,
        complexity: 8,
        signalType: .voice
    )

    static let highQuality = OpusEncoderConfig(
        application: .audio,
        bitrate: 64000,
        frameSize: 960,
        complexity: 10,
        signalType: .auto
    )
}

// MARK: - AudioCodec

final class AudioCodec {

    // MARK: - Properties

    weak var delegate: AudioCodecDelegate?

    private(set) var codecType: AudioCodecType
    private(set) var inputFormat: AudioFormat
    private(set) var outputFormat: AudioFormat
    private(set) var isRunning: Bool = false

    private var encoderFormat: AudioStreamBasicDescription?
    private var decoderFormat: AudioStreamBasicDescription?

    private let codecQueue = DispatchQueue(label: "com.voice.audiocodec", qos: .userInitiated)

    // PCM Buffer
    private var pcmBuffer: AVAudioPCMBuffer?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // MARK: - Initialization

    init(codecType: AudioCodecType, inputFormat: AudioFormat = .defaultFormat) {
        self.codecType = codecType
        self.inputFormat = inputFormat
        self.outputFormat = inputFormat
        self.state = CodecState()
    }

    // MARK: - Codec State
    struct CodecState {
        var encodedFrames: Int = 0
        var decodedFrames: Int = 0
        var droppedFrames: Int = 0
        var averageEncodeTime: TimeInterval = 0
        var averageDecodeTime: TimeInterval = 0
    }

    private(set) var state = CodecState()

    func resetState() {
        state = CodecState()
    }

    func updateEncodedFrame(encodeTime: TimeInterval) {
        state.encodedFrames += 1
        state.averageEncodeTime = (state.averageEncodeTime * Double(state.encodedFrames - 1) + encodeTime) / Double(state.encodedFrames)
    }

    func updateDecodedFrame(decodeTime: TimeInterval) {
        state.decodedFrames += 1
        state.averageDecodeTime = (state.averageDecodeTime * Double(state.decodedFrames - 1) + decodeTime) / Double(state.decodedFrames)
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    func start() throws {
        guard !isRunning else { return }

        switch codecType {
        case .opus:
            try setupOpusCodec()
        case .pcm:
            try setupPCMCodec()
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }

        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        pcmBuffer = nil

        isRunning = false
    }

    func encode(_ pcmData: Data) throws -> Data {
        guard isRunning else {
            throw AudioCodecError.codecNotAvailable
        }

        switch codecType {
        case .opus:
            return try encodeOpus(pcmData)
        case .pcm:
            return pcmData
        }
    }

    func decode(_ encodedData: Data) throws -> Data {
        guard isRunning else {
            throw AudioCodecError.codecNotAvailable
        }

        switch codecType {
        case .opus:
            return try decodeOpus(encodedData)
        case .pcm:
            return encodedData
        }
    }

    func flush() {
        pcmBuffer = nil
    }

    // MARK: - PCM Audio Session

    func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }

    func createInputPipeline() throws -> AVAudioInputNode {
        guard let engine = audioEngine else {
            throw AudioCodecError.codecNotAvailable
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        self.inputNode = inputNode
        self.encoderFormat = inputFormat.streamDescription.pointee

        return inputNode
    }

    // MARK: - Opus Codec

    private func setupOpusCodec() throws {
        audioEngine = AVAudioEngine()
        try setupAudioSession()
    }

    private func encodeOpus(_ pcmData: Data) throws -> Data {
        return pcmData
    }

    private func decodeOpus(_ encodedData: Data) throws -> Data {
        return encodedData
    }

    // MARK: - PCM Codec

    private func setupPCMCodec() throws {
        audioEngine = AVAudioEngine()
        try setupAudioSession()
    }

    // MARK: - Format Conversion Helpers

    func pcmToAudioBuffer(_ pcmData: Data, format: AudioFormat) -> AVAudioPCMBuffer? {
        guard let frameCount = AVAudioFrameCount(exactly: pcmData.count / (format.bitsPerChannel / 8) / format.channelCount) else {
            return nil
        }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioStreamFormat(for: format), frameCapacity: frameCount) else {
            return nil
        }

        pcmBuffer.frameLength = frameCount

        let channels = pcmBuffer.floatChannelData
        pcmData.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else { return }
            let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
            for channel in 0..<format.channelCount {
                for frame in 0..<Int(frameCount) {
                    channels?[channel][frame] = floatPointer[frame * format.channelCount + channel]
                }
            }
        }

        return pcmBuffer
    }

    func audioBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatChannelData = buffer.floatChannelData else {
            return Data()
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var pcmData = Data(capacity: frameCount * channelCount * MemoryLayout<Float>.size)

        for frame in 0..<frameCount {
            for channel in 0..<channelCount {
                let sample = floatChannelData[channel][frame]
                withUnsafeBytes(of: sample) { pcmData.append(contentsOf: $0) }
            }
        }

        return pcmData
    }

    private func audioStreamFormat(for format: AudioFormat) -> AVAudioFormat {
        return AVAudioFormat(
            commonFormat: format.isFloat ? .pcmFormatFloat32 : .pcmFormatInt16,
            sampleRate: format.sampleRate,
            channels: AVAudioChannelCount(format.channelCount),
            interleaved: false
        )!
    }

    // MARK: - Opus Specific Configuration

    func configureOpus(_ config: OpusEncoderConfig) {
    }

    func getOpusDecoderCapabilities() -> (sampleRate: Int, channels: Int) {
        return (48000, 1)
    }

    // MARK: - Frame Size Calculator

    func calculateFrameSize(for duration: TimeInterval, format: AudioFormat) -> Int {
        return Int(format.sampleRate * duration)
    }

    // MARK: - Bitrate Calculator

    func calculateBitrate(frameSize: Int, format: AudioFormat) -> Int {
        return (frameSize * format.bitsPerChannel * format.channelCount) / Int(format.sampleRate)
    }
}

// MARK: - AudioCodec Buffer Management

extension AudioCodec {

    func appendPCMData(_ data: Data) {
        var combined = Data()
        if let existing = pcmBuffer {
            combined.append(audioBufferToData(existing))
        }
        combined.append(data)

        if let newBuffer = pcmToAudioBuffer(combined, format: inputFormat) {
            pcmBuffer = newBuffer
        }
    }

    func extractFrame(size: Int) -> Data? {
        guard let buffer = pcmBuffer else { return nil }

        let currentSize = Int(buffer.frameLength) * inputFormat.channelCount * (inputFormat.bitsPerChannel / 8)

        guard currentSize >= size else { return nil }

        let frameData = audioBufferToData(buffer).prefix(size)

        return Data(frameData)
    }

    func clearBuffer() {
        pcmBuffer = nil
    }
}

// MARK: - AudioCodec State

extension AudioCodec {

    // Methods already defined in main class body
}
