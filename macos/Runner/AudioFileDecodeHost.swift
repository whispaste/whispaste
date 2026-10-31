import AVFoundation
import Cocoa
import FlutterMacOS

/// MethodChannel host that decodes compressed audio files (MP3, FLAC, M4A/AAC)
/// to the STT input format (16 kHz, mono, 16-bit little-endian PCM) with
/// Apple's own AVFoundation, so the app ships no third-party decoder. Ogg/Opus
/// has no AVFoundation decoder; it goes to the shared C++ core through
/// `WhispasteOpusDecode.h`, which uses the bundled libopusfile (WP-35b).
///
/// Contract (`whispaste/audio_file_decode`, method `decodeToPcm16`):
/// - arguments: `inputPath` (a copy inside the app container, never the
///   user's original), `outputPath` (raw PCM file to create).
/// - result: frame count as `Int`.
/// - errors: `UNSUPPORTED_FORMAT` when the file cannot be opened or read,
///   `UNAVAILABLE` when a decoder is missing, `INPUT_LIMIT` past six hours,
///   `DECODE_FAILED` for read or conversion errors.
///
/// The Dart side wraps the raw PCM into a canonical WAV header.
/// Domain and code of [error] for native error messages. The localized text is
/// left out on purpose: file-system errors embed the file path in it, and the
/// message ends up in logs.
private func describeError(_ error: Error) -> String {
  let ns = error as NSError
  return "\(ns.domain) code \(ns.code)"
}

class AudioFileDecodeHost {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "whispaste.audio-file-decode", qos: .utility)

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "whispaste/audio_file_decode",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "decodeToPcm16" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let inputPath = args["inputPath"] as? String,
          let outputPath = args["outputPath"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "Missing inputPath or outputPath", details: nil))
      return
    }
    queue.async {
      do {
        let frames = try Self.decode(
          input: URL(fileURLWithPath: inputPath),
          output: URL(fileURLWithPath: outputPath)
        )
        DispatchQueue.main.async { result(frames) }
      } catch DecodeError.unsupported {
        DispatchQueue.main.async {
          result(FlutterError(code: "UNSUPPORTED_FORMAT", message: "AVFoundation cannot open this file", details: nil))
        }
      } catch DecodeError.unavailable {
        DispatchQueue.main.async {
          result(FlutterError(code: "UNAVAILABLE", message: "decoder not available", details: nil))
        }
      } catch DecodeError.io(let message) {
        DispatchQueue.main.async {
          result(FlutterError(code: "IO_ERROR", message: message, details: nil))
        }
      } catch DecodeError.inputLimit {
        DispatchQueue.main.async {
          result(FlutterError(code: "INPUT_LIMIT", message: "audio longer than six hours", details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "DECODE_FAILED", message: describeError(error), details: nil))
        }
      }
    }
  }

  private enum DecodeError: Error {
    case unsupported
    case unavailable
    case inputLimit
    case io(String)
    case failed(String)
  }

  /// Six hours at 16 kHz, the ceiling every platform host enforces.
  private static let maxOutputFrames: Int64 = 6 * 3600 * 16000

  private static func isOgg(_ url: URL) -> Bool {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    return handle.readData(ofLength: 4) == Data("OggS".utf8)
  }

  /// Ogg/Opus through the shared core. The core creates the output file itself.
  private static func decodeOgg(input: URL, output: URL) throws -> Int {
    var frames: Int64 = 0
    var message = [CChar](repeating: 0, count: 256)
    // Six hours at 16 kHz: the same ceiling the Linux and Windows hosts use.
    let maxFrames = maxOutputFrames
    let status = wp_decode_ogg_to_pcm16(
      input.path, output.path, maxFrames, &frames, &message, message.count
    )
    switch status {
    case WP_DECODE_OK:
      return Int(frames)
    case WP_DECODE_UNSUPPORTED:
      throw DecodeError.unsupported
    case WP_DECODE_INPUT_LIMIT:
      throw DecodeError.inputLimit
    case WP_DECODE_UNAVAILABLE:
      throw DecodeError.unavailable
    case WP_DECODE_IO_ERROR:
      throw DecodeError.io(String(cString: message))
    default:
      throw DecodeError.failed(String(cString: message))
    }
  }

  private static func decode(input: URL, output: URL) throws -> Int {
    if isOgg(input) {
      return try decodeOgg(input: input, output: output)
    }
    let file: AVAudioFile
    do {
      file = try AVAudioFile(forReading: input)
    } catch {
      throw DecodeError.unsupported
    }
    let source = file.processingFormat
    // Refuse by length before any conversion or write: the source length in
    // frames, scaled to 16 kHz, must stay within the six-hour ceiling.
    let expectedOutput = Double(file.length) * 16000 / source.sampleRate
    if expectedOutput > Double(maxOutputFrames) {
      throw DecodeError.inputLimit
    }
    guard let target = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 16000,
      channels: 1,
      interleaved: true
    ), let converter = AVAudioConverter(from: source, to: target) else {
      throw DecodeError.failed("no converter for \(source)")
    }
    // Stereo to mono must mix both channels; without downmix a stereo source
    // with signal only on the right channel converts to silence.
    converter.downmix = true

    guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
      throw DecodeError.io("cannot create output")
    }
    let handle: FileHandle
    do {
      handle = try FileHandle(forWritingTo: output)
    } catch {
      throw DecodeError.io("cannot open output: \(describeError(error))")
    }
    defer { try? handle.close() }

    let inputCapacity: AVAudioFrameCount = 8192
    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: inputCapacity) else {
      throw DecodeError.failed("input buffer")
    }
    let outputCapacity = AVAudioFrameCount(Double(inputCapacity) * 16000 / source.sampleRate) + 1024
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputCapacity) else {
      throw DecodeError.failed("output buffer")
    }

    var totalFrames = 0
    var readError: Error?
    var inputExhausted = false
    while true {
      outputBuffer.frameLength = 0
      var conversionError: NSError?
      let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
        // Reading at or past the end throws on some codecs, so stop by position.
        if inputExhausted || file.framePosition >= file.length {
          inputExhausted = true
          outStatus.pointee = .endOfStream
          return nil
        }
        do {
          try file.read(into: inputBuffer)
        } catch {
          readError = error
          inputExhausted = true
          outStatus.pointee = .endOfStream
          return nil
        }
        if inputBuffer.frameLength == 0 {
          inputExhausted = true
          outStatus.pointee = .endOfStream
          return nil
        }
        outStatus.pointee = .haveData
        return inputBuffer
      }

      if let readError = readError {
        throw DecodeError.failed("read: \(readError)")
      }
      if let conversionError = conversionError {
        throw DecodeError.failed("convert: \(conversionError)")
      }
      let frames = Int(outputBuffer.frameLength)
      if frames > 0, let samples = outputBuffer.int16ChannelData?[0] {
        // Stop in the loop as soon as the ceiling is reached, not only after.
        if Int64(totalFrames + frames) > maxOutputFrames {
          throw DecodeError.inputLimit
        }
        do {
          try handle.write(contentsOf: Data(bytes: samples, count: frames * MemoryLayout<Int16>.size))
        } catch {
          throw DecodeError.io("write: \(describeError(error))")
        }
        totalFrames += frames
      }
      if status == .endOfStream || status == .error {
        break
      }
    }
    return totalFrames
  }
}
