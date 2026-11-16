import AVFoundation
import FlutterMacOS
import Speech

/// MethodChannel host for the system speech engine (SpeechAnalyzer with a
/// SpeechTranscriber, macOS 26 and later). Runs entirely on device; the
/// system owns the language assets, so the app ships no speech model for it.
///
/// Channel `whispaste/system_speech`:
/// - `capability` (`locale`): map with `osSupported`, `localeSupported`
///   (the system's own locale identifier or `nil`) and `installed`.
/// - `installAsset` (`locale`): starts the system asset download. Returns at
///   once; progress is read with `installProgress`.
/// - `installProgress`: map with `state` (`idle`, `installing`, `done`,
///   `error`), `fraction` (0...1) and `code` (cause, set on `error`).
/// - `prewarm` (`locale`): loads the model for the locale ahead of a dictation.
/// - `transcribe` (`path`, `locale`, `terms`): transcribes a WAV file and
///   returns the text. `terms` are vocabulary hints for the recognizer.
/// - `cancel`: stops a running `transcribe`, which then answers `CANCELLED`.
/// - `liveStart` (`locale`, `terms`): opens a streaming analyzer for the live
///   preview during recording (#1078). Answers `true` once it runs, `false`
///   when it cannot (asset missing, no reservation); the preview then stays
///   off and the recording is unaffected. Interim text arrives as host-to-Dart
///   `livePartial` calls (the full text so far, finalized plus volatile).
/// - `liveFeed` (`pcm`): 16 kHz mono 16-bit little-endian samples.
/// - `liveStop`: ends the stream. The preview never produces the final
///   transcript; that always comes from `transcribe` on the saved WAV.
///
/// `locale` is always the language chosen in Settings; an empty locale is
/// unsupported, never read as the system language.
///
/// Errors carry only a code, never text: the user-facing wording lives in Dart
/// and the ARB files. Every SpeechAnalyzer call sits behind `macOS 26` checks,
/// because the app's deployment target is older.
final class SystemSpeechHost {
  private let channel: FlutterMethodChannel
  private var installState = "idle"
  private var installFraction = 0.0
  private var installErrorCode = ""
  private var installProgress: Progress?
  private var installTask: Task<Void, Never>?
  private var transcribeTask: Task<Void, Never>?
  private var liveBox: AnyObject?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "whispaste/system_speech",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  deinit {
    installTask?.cancel()
    transcribeTask?.cancel()
  }

  @available(macOS 26.0, *)
  private var live: SystemSpeechLive? {
    get { liveBox as? SystemSpeechLive }
    set { liveBox = newValue }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(macOS 26.0, *) else {
      switch call.method {
      case "capability":
        result(["osSupported": false, "localeSupported": NSNull(), "installed": false])
      case "installProgress":
        result(["state": "idle", "fraction": 0.0, "code": ""])
      case "prewarm", "cancel", "liveFeed", "liveStop":
        result(nil)
      case "liveStart":
        result(false)
      default:
        result(FlutterError(code: "OS_UNSUPPORTED", message: nil, details: nil))
      }
      return
    }
    let args = call.arguments as? [String: Any]
    let locale = args?["locale"] as? String ?? ""
    switch call.method {
    case "capability":
      Task { @MainActor in
        result(await SystemSpeechEngine.capability(locale: locale))
      }
    case "installAsset":
      startInstall(locale: locale, result: result)
    case "installProgress":
      result(currentProgress())
    case "prewarm":
      Task { @MainActor in
        await SystemSpeechEngine.prewarm(locale: locale)
        result(nil)
      }
    case "transcribe":
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
        return
      }
      let terms = args?["terms"] as? [String] ?? []
      transcribeTask?.cancel()
      transcribeTask = Task { @MainActor in
        do {
          let text = try await SystemSpeechEngine.transcribe(path: path, locale: locale, terms: terms)
          result(text)
        } catch let error as SystemSpeechEngine.Failure {
          result(FlutterError(code: error.code, message: nil, details: nil))
        } catch is CancellationError {
          result(FlutterError(code: "CANCELLED", message: nil, details: nil))
        } catch {
          result(FlutterError(code: Task.isCancelled ? "CANCELLED" : "TRANSCRIBE_FAILED", message: nil, details: nil))
        }
      }
    case "liveStart":
      let terms = args?["terms"] as? [String] ?? []
      let previous = live
      // Channel handlers run on the main thread, so main-actor access is safe.
      let session = MainActor.assumeIsolated {
        SystemSpeechLive { [weak self] text in
          self?.channel.invokeMethod("livePartial", arguments: text)
        }
      }
      live = session
      Task { @MainActor in
        await previous?.stop()
        let started = await session.start(locale: locale, terms: terms)
        if !started, self.live === session { self.live = nil }
        result(started)
      }
    case "liveFeed":
      if let data = (call.arguments as? [String: Any])?["pcm"] as? FlutterStandardTypedData {
        MainActor.assumeIsolated { live?.feed(data.data) }
      }
      result(nil)
    case "liveStop":
      let session = live
      live = nil
      Task { @MainActor in
        await session?.stop()
        result(nil)
      }
    case "cancel":
      transcribeTask?.cancel()
      transcribeTask = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(macOS 26.0, *)
  private func startInstall(locale: String, result: @escaping FlutterResult) {
    if installState == "installing" {
      result(nil)
      return
    }
    installState = "installing"
    installFraction = 0
    installErrorCode = ""
    installTask = Task { @MainActor in
      var request: AssetInstallationRequest?
      do {
        request = try await SystemSpeechEngine.installationRequest(locale: locale)
      } catch let error as SystemSpeechEngine.Failure {
        self.fail(code: error.code)
        return
      } catch {
        self.fail(code: "REQUEST_FAILED")
        return
      }
      self.installProgress = request?.progress
      do {
        try await request?.downloadAndInstall()
        self.installFraction = 1
        self.installState = "done"
      } catch {
        self.fail(code: "DOWNLOAD_FAILED")
      }
      self.installProgress = nil
    }
    result(nil)
  }

  private func fail(code: String) {
    installErrorCode = code
    installState = "error"
    installProgress = nil
    installTask?.cancel()
    installTask = nil
  }

  private func currentProgress() -> [String: Any] {
    if let progress = installProgress {
      installFraction = progress.fractionCompleted
    }
    return ["state": installState, "fraction": installFraction, "code": installErrorCode]
  }
}

/// The SpeechAnalyzer calls, isolated behind the macOS 26 availability.
@available(macOS 26.0, *)
enum SystemSpeechEngine {
  struct Failure: Error {
    let code: String
  }

  /// The system's locale for [locale], or `nil` when the system cannot
  /// transcribe it. An empty [locale] is unsupported: the engine never falls
  /// back to the system language. Resolution in two tiers: language and region, then language alone. The
  /// tags are rebuilt from their parts, because the user's locale may carry
  /// extensions that no engine knows (for example `@rg=...`).
  static func supportedLocale(_ locale: String) async -> Locale? {
    guard !locale.isEmpty else { return nil }
    let requested = Locale(identifier: locale)
    guard let language = requested.language.languageCode?.identifier else { return nil }
    var candidates: [Locale] = []
    if let region = requested.region?.identifier {
      candidates.append(Locale(identifier: "\(language)_\(region)"))
    }
    candidates.append(Locale(identifier: language))
    for candidate in candidates {
      if let found = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
        return found
      }
    }
    return nil
  }

  /// The transcription module. Assets, status and transcription all use this
  /// same module, so they always agree. SpeechTranscriber punctuates on its
  /// own; DictationTranscriber returned no punctuation for German in the
  /// reference measurement (#60), even with `.punctuation`.
  static func module(_ locale: Locale) -> SpeechTranscriber {
    SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [],
      attributeOptions: []
    )
  }

  static func capability(locale: String) async -> [String: Any] {
    guard SpeechTranscriber.isAvailable else {
      return ["osSupported": true, "localeSupported": NSNull(), "installed": false]
    }
    guard let supported = await supportedLocale(locale) else {
      return ["osSupported": true, "localeSupported": NSNull(), "installed": false]
    }
    let status = await AssetInventory.status(forModules: [module(supported)])
    return [
      "osSupported": true,
      "localeSupported": supported.identifier,
      "installed": status == .installed,
    ]
  }

  static func installationRequest(locale: String) async throws -> AssetInstallationRequest? {
    guard let supported = await supportedLocale(locale) else {
      throw Failure(code: "LOCALE_UNSUPPORTED")
    }
    return try await AssetInventory.assetInstallationRequest(supporting: [module(supported)])
  }

  /// The locale this app reserved itself, or `nil`. Only this reservation is
  /// ever released, and only when the language changes; a reservation another
  /// component holds stays untouched.
  @MainActor private static var ownedReservation: Locale?

  /// Makes sure [locale] is reserved, once per language rather than per run.
  /// Returns `false` when the system refuses (reservation limit reached).
  @MainActor static func ensureReservation(_ locale: Locale) async throws -> Bool {
    let reserved = await AssetInventory.reservedLocales.map(\.identifier)
    if reserved.contains(locale.identifier) { return true }
    if let previous = ownedReservation, previous.identifier != locale.identifier {
      await AssetInventory.release(reservedLocale: previous)
      ownedReservation = nil
    }
    guard try await AssetInventory.reserve(locale: locale) else { return false }
    ownedReservation = locale
    return true
  }

  /// Reserves the locale and loads its model ahead of the first dictation.
  /// The reservation comes first: the asset status reads `installed` only for
  /// a process that holds the locale's reservation, so after an app restart
  /// the status check alone would skip the prewarm. Failures are silent here:
  /// the first dictation reports them properly.
  static func prewarm(locale: String) async {
    guard let supported = await supportedLocale(locale) else { return }
    guard let reserved = try? await ensureReservation(supported), reserved else { return }
    let transcriber = module(supported)
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else { return }
    let analyzer = SpeechAnalyzer(
      modules: [transcriber],
      options: SpeechAnalyzer.Options(priority: .utility, modelRetention: .lingering)
    )
    _ = try? await analyzer.prepareToAnalyze(in: nil)
    await analyzer.cancelAndFinishNow()
  }

  static func transcribe(path: String, locale: String, terms: [String]) async throws -> String {
    guard SpeechTranscriber.isAvailable else {
      throw Failure(code: "OS_UNSUPPORTED")
    }
    guard let supported = await supportedLocale(locale) else {
      throw Failure(code: "LOCALE_UNSUPPORTED")
    }
    // Reserve before reading the status: it reads `installed` only for a
    // process that holds the reservation (see `prewarm`).
    guard try await ensureReservation(supported) else {
      throw Failure(code: "RESERVATION_LIMIT")
    }
    let transcriber = module(supported)
    guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
      throw Failure(code: "ASSET_MISSING")
    }

    let analyzer = SpeechAnalyzer(
      modules: [transcriber],
      options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
    )
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let seconds = Double(file.length) / file.processingFormat.sampleRate
    let limit = max(20.0, seconds * 4 + 10)
    do {
      return try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: String.self) { group in
        defer { group.cancelAll() }
        group.addTask {
          try await run(analyzer: analyzer, transcriber: transcriber, file: file, terms: terms)
        }
        group.addTask {
          try await Task.sleep(for: .seconds(limit))
          throw Failure(code: "TIMEOUT")
        }
        guard let text = try await group.next() else {
          throw Failure(code: "TRANSCRIBE_FAILED")
        }
        return text
        }
      } onCancel: {
        // Cancelled by the host (Dart gave up): stop the analyzer at once.
        Task { await analyzer.cancelAndFinishNow() }
      }
    } catch {
      // Timeout or failure: stop the analyzer so no work keeps running.
      await analyzer.cancelAndFinishNow()
      throw error
    }
  }

  private static func run(
    analyzer: SpeechAnalyzer,
    transcriber: SpeechTranscriber,
    file: AVAudioFile,
    terms: [String]
  ) async throws -> String {
    let collector = Task { () throws -> String in
      var text = ""
      for try await result in transcriber.results {
        text += String(result.text.characters)
      }
      return text
    }
    do {
      if !terms.isEmpty {
        let context = AnalysisContext()
        context.contextualStrings[.general] = terms
        try await analyzer.setContext(context)
      }
      try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
      let text = try await collector.value
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      collector.cancel()
      throw error
    }
  }
}

/// Streaming analyzer for the live preview. Separate from `transcribe`: it
/// only ever reports interim text, never the final transcript.
@available(macOS 26.0, *)
@MainActor
final class SystemSpeechLive {
  private let onText: (String) -> Void
  private var analyzer: SpeechAnalyzer?
  private var continuation: AsyncStream<AnalyzerInput>.Continuation?
  private var resultsTask: Task<Void, Never>?
  private var converter: AVAudioConverter?
  private var targetFormat: AVAudioFormat?
  private let sourceFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true
  )!

  init(onText: @escaping (String) -> Void) {
    self.onText = onText
  }

  func start(locale: String, terms: [String]) async -> Bool {
    guard SpeechTranscriber.isAvailable,
      let supported = await SystemSpeechEngine.supportedLocale(locale),
      (try? await SystemSpeechEngine.ensureReservation(supported)) == true
    else { return false }
    let transcriber = SpeechTranscriber(
      locale: supported,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults],
      attributeOptions: []
    )
    guard await AssetInventory.status(forModules: [transcriber]) == .installed,
      let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
      let converter = AVAudioConverter(from: sourceFormat, to: format)
    else { return false }
    let analyzer = SpeechAnalyzer(
      modules: [transcriber],
      options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .lingering)
    )
    do {
      if !terms.isEmpty {
        let context = AnalysisContext()
        context.contextualStrings[.general] = terms
        try await analyzer.setContext(context)
      }
      let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
      self.analyzer = analyzer
      self.continuation = continuation
      self.converter = converter
      self.targetFormat = format
      let emit = onText
      resultsTask = Task {
        var finalized = ""
        do {
          for try await result in transcriber.results {
            let text = String(result.text.characters)
            if result.isFinal {
              finalized += text
              emit(finalized)
            } else {
              emit(finalized + text)
            }
          }
        } catch {}
      }
      try await analyzer.start(inputSequence: stream)
      return true
    } catch {
      await stop()
      return false
    }
  }

  func feed(_ pcm: Data) {
    guard let continuation, let converter, let targetFormat else { return }
    let frames = AVAudioFrameCount(pcm.count / 2)
    guard frames > 0,
      let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frames)
    else { return }
    input.frameLength = frames
    pcm.withUnsafeBytes { raw in
      if let base = raw.baseAddress, let dst = input.int16ChannelData?[0] {
        memcpy(dst, base, Int(frames) * 2)
      }
    }
    let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
    let capacity = AVAudioFrameCount(Double(frames) * ratio) + 16
    guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
    var consumed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return input
    }
    if error == nil, output.frameLength > 0 {
      continuation.yield(AnalyzerInput(buffer: output))
    }
  }

  func stop() async {
    continuation?.finish()
    continuation = nil
    resultsTask?.cancel()
    resultsTask = nil
    let analyzer = self.analyzer
    self.analyzer = nil
    converter = nil
    await analyzer?.cancelAndFinishNow()
  }
}
