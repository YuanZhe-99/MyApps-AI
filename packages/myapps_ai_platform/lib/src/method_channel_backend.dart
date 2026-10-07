import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// The real backend, talking to `GenAiChannel` on Android and the
/// `on_device_ai_apple` plugin on iOS and macOS, over one channel name.
class MethodChannelGenAiBackend extends CapabilityGenAiBackend {
  /// Purpose: Create the channel backend.
  /// Inputs: `channel` — injectable for tests.
  /// Returns: A new `MethodChannelGenAiBackend`.
  /// Side effects: None.
  /// Notes: Nothing is sent until a method is called.
  MethodChannelGenAiBackend([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  /// The channel name, matched by `GenAiChannel.CHANNEL` in Kotlin and the
  /// Apple plugin's registration.
  static const channelName = 'com.yuanzhe.myapps_ai/genai';

  final MethodChannel _channel;

  void Function(int bytes, int total)? _onProgress;
  bool _listening = false;

  /// Purpose: Ask the platform for the model's status.
  /// Inputs: `force`, `preferFast`.
  /// Returns: `Future<GenAiStatusReport>`.
  /// Side effects: One channel call.
  /// Notes: A `MissingPluginException` is [GenAiStatus.unreachable] with the
  /// detail "channel not registered" — never `unsupported` — so a plugin that
  /// failed to register is noticed.
  @override
  Future<GenAiStatusReport> statusReport({
    bool force = false,
    bool preferFast = false,
  }) => capabilityReport(
    GenAiFeature.prompt,
    force: force,
    preferFast: preferFast,
  );

  /// Purpose: Query capability. Inputs: feature, force, preferFast.
  /// Returns: Status. Side effects: Channel call. Notes: Apple proofreading is unsupported.
  @override
  Future<GenAiStatusReport> capabilityReport(
    GenAiFeature feature, {
    bool force = false,
    bool preferFast = false,
  }) async {
    if (!platformMayHaveOnDeviceModel) return GenAiStatusReport.unsupported;
    if (feature == GenAiFeature.proofread &&
        defaultTargetPlatform != TargetPlatform.android) {
      return GenAiStatusReport.unsupported;
    }
    try {
      final answer = await _channel.invokeMapMethod<Object?, Object?>(
        'status',
        {'feature': feature.name, 'force': force, 'preferFast': preferFast},
      );
      return GenAiStatusReport.fromJson(answer);
    } on MissingPluginException {
      return const GenAiStatusReport(
        GenAiStatus.unreachable,
        detail: 'channel not registered',
      );
    } on PlatformException catch (error) {
      return GenAiStatusReport(
        GenAiStatus.unreachable,
        detail: '${error.code}: ${error.message}',
      );
    } catch (error) {
      return GenAiStatusReport(
        GenAiStatus.unreachable,
        detail: error.runtimeType.toString(),
      );
    }
  }

  /// Purpose: Read the device's model-system details.
  /// Inputs: `localeTag`.
  /// Returns: `Future<GenAiCoreInfo?>` — null off the supported platforms and
  /// whenever the call fails.
  /// Side effects: One channel call.
  /// Notes: A diagnostic; failing to gather it never breaks Settings.
  @override
  Future<GenAiCoreInfo?> coreInfo({String? localeTag}) async {
    if (!platformMayHaveOnDeviceModel) return null;
    try {
      return GenAiCoreInfo.fromJson(
        await _channel.invokeMapMethod<Object?, Object?>('info', {
          'locale': ?localeTag,
        }),
      );
    } catch (_) {
      return null;
    }
  }

  /// Purpose: Ask the system to fetch the model.
  /// Inputs: `onProgress`.
  /// Returns: `Future<bool>`.
  /// Side effects: The system downloads a model; progress arrives as method
  /// calls from the platform.
  /// Notes: The progress handler is registered lazily and once.
  @override
  Future<bool> download({void Function(int bytes, int total)? onProgress}) =>
      downloadCapability(GenAiFeature.prompt, onProgress: onProgress);

  /// Purpose: Download capability. Inputs: feature, progress.
  /// Returns: Readiness. Side effects: Channel call. Notes: System owns model storage.
  @override
  Future<bool> downloadCapability(
    GenAiFeature feature, {
    void Function(int, int)? onProgress,
  }) async {
    if (!platformMayHaveOnDeviceModel) {
      throw const GenAiException(GenAiFailure.unavailable);
    }
    _onProgress = onProgress;
    if (!_listening) {
      _channel.setMethodCallHandler(_handlePlatformCall);
      _listening = true;
    }
    try {
      final done = await _channel.invokeMethod<bool>('download', {
        'feature': feature.name,
      });
      return done ?? false;
    } on PlatformException catch (e) {
      throw GenAiException(failureForCode(e.code), e.message);
    } on MissingPluginException catch (e) {
      throw GenAiException(GenAiFailure.unavailable, e.message);
    } finally {
      _onProgress = null;
    }
  }

  /// Purpose: Generate one answer.
  /// Inputs: `instructions`, `prompt`, `maxOutputTokens`, `temperature`,
  /// `topK`.
  /// Returns: `Future<String>`.
  /// Side effects: Runs the model on the device.
  /// Notes: None.
  @override
  Future<String> generate({
    required String instructions,
    required String prompt,
    int maxOutputTokens = 256,
    double temperature = 0,
    int topK = 1,
  }) async {
    if (!platformMayHaveOnDeviceModel) {
      throw const GenAiException(GenAiFailure.unavailable);
    }
    try {
      final text = await _channel.invokeMethod<String>('generate', {
        'instructions': instructions,
        'prompt': prompt,
        'maxOutputTokens': maxOutputTokens,
        'temperature': temperature,
        'topK': topK,
      });
      return text ?? '';
    } on PlatformException catch (e) {
      throw GenAiException(failureForCode(e.code), e.message);
    } on MissingPluginException catch (e) {
      throw GenAiException(GenAiFailure.unavailable, e.message);
    }
  }

  /// Purpose: Pick up to `maxItems` of `options`.
  /// Inputs: `instructions`, `prompt`, `options`, `maxItems`.
  /// Returns: `Future<List<String>>`.
  /// Side effects: Runs the model on the device.
  /// Notes: Apple answers natively with constrained decoding; Android
  /// generates text and [parseChoiceReply] reads it. A reply that ignores the
  /// format is a [GenAiFailure.failed].
  @override
  Future<List<String>> choose({
    required String instructions,
    required String prompt,
    required List<String> options,
    int maxItems = 3,
  }) async {
    if (!platformMayHaveOnDeviceModel) {
      throw const GenAiException(GenAiFailure.unavailable);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final reply = await generate(
        instructions: instructions,
        prompt: prompt,
        maxOutputTokens: 64,
      );
      final parsed = parseChoiceReply(reply, options, maxItems: maxItems);
      if (!parsed.valid) {
        throw const GenAiException(GenAiFailure.failed, 'unparseable reply');
      }
      return parsed.ids;
    }
    try {
      final chosen = await _channel.invokeListMethod<Object?>('choose', {
        'instructions': instructions,
        'prompt': prompt,
        'options': options,
        'maxItems': maxItems,
      });
      return [
        for (final c in chosen ?? const <Object?>[])
          if (c is String) c,
      ];
    } on PlatformException catch (e) {
      throw GenAiException(failureForCode(e.code), e.message);
    } on MissingPluginException catch (e) {
      throw GenAiException(GenAiFailure.unavailable, e.message);
    }
  }

  /// Purpose: Load the model ahead of a batch.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: One channel call.
  /// Notes: Errors are swallowed; prewarming is advisory.
  @override
  Future<void> prewarm() async {
    if (!platformMayHaveOnDeviceModel) return;
    try {
      await _channel.invokeMethod<void>('prewarm');
    } catch (_) {
      // Advisory only.
    }
  }

  /// Purpose: Proofread Japanese keyboard text. Inputs: text.
  /// Returns: Suggestions. Side effects: Channel call. Notes: No generation fallback.
  @override
  Future<List<String>> proofread(String text) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const GenAiException(GenAiFailure.unavailable);
    }
    try {
      return await _channel.invokeListMethod<String>('proofread', {
            'text': text,
          }) ??
          [];
    } on PlatformException catch (e) {
      throw GenAiException(failureForCode(e.code), e.message);
    } on MissingPluginException catch (e) {
      throw GenAiException(GenAiFailure.unavailable, e.message);
    }
  }

  /// Purpose: Stop whatever is running.
  /// Inputs: None.
  /// Returns: None.
  /// Side effects: Cancels the in-flight platform request.
  /// Notes: Errors are swallowed; cancelling is best effort.
  @override
  Future<void> cancel() async {
    if (!platformMayHaveOnDeviceModel) return;
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {
      // The request either finished or will be discarded.
    }
  }

  /// Purpose: Receive download progress from the platform.
  /// Inputs: `call`.
  /// Returns: None.
  /// Side effects: Calls the current progress callback.
  /// Notes: Internal helper used within this file only.
  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'downloadProgress') return;
    final args = call.arguments;
    if (args is! Map) return;
    _onProgress?.call(
      (args['bytes'] as num?)?.toInt() ?? 0,
      (args['total'] as num?)?.toInt() ?? -1,
    );
  }

  /// Purpose: Map a platform error code to a failure.
  /// Inputs: `code`.
  /// Returns: `GenAiFailure`.
  /// Side effects: None.
  /// Notes: The codes `GenAiChannel` and the Apple plugin send; anything else
  /// is `failed`.
  @visibleForTesting
  static GenAiFailure failureForCode(String code) => switch (code) {
    'unavailable' => GenAiFailure.unavailable,
    'busy' => GenAiFailure.busy,
    'cancelled' => GenAiFailure.cancelled,
    'tooLong' => GenAiFailure.tooLong,
    'background' => GenAiFailure.background,
    'quota' => GenAiFailure.quota,
    'guardrail' => GenAiFailure.guardrail,
    'unsupportedLanguage' => GenAiFailure.unsupportedLanguage,
    _ => GenAiFailure.failed,
  };
}
