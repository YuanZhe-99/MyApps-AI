/// Backend-neutral text LLM contracts: messages, sampling, streaming and the
/// adapter onto the existing `GenAiBackend` prompt contract.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Who wrote a chat message.
enum LlmRole { system, user, assistant }

/// One chat message.
@immutable
class LlmMessage {
  /// Purpose: Create a message. Inputs: `role`, `content`.
  /// Returns: A new message. Side effects: None. Notes: None.
  const LlmMessage(this.role, this.content);

  /// The author.
  final LlmRole role;

  /// The text.
  final String content;

  /// Purpose: Serialize for HTTP or native bridges.
  /// Inputs: None. Returns: JSON map. Side effects: None.
  /// Notes: Field names follow the OpenAI chat shape.
  Map<String, Object?> toJson() => {'role': role.name, 'content': content};
}

/// Sampling and length limits for one request.
@immutable
class LlmSampling {
  /// Purpose: Describe sampling.
  /// Inputs: `maxOutputTokens`, `temperature`, `topK`, `topP`, `seed`, `stop`.
  /// Returns: A new value. Side effects: None.
  /// Notes: Defaults are deterministic to match existing prompt behavior.
  const LlmSampling({
    this.maxOutputTokens = 256,
    this.temperature = 0,
    this.topK = 1,
    this.topP,
    this.seed,
    this.stop = const [],
  });

  final int maxOutputTokens;
  final double temperature;
  final int topK;
  final double? topP;
  final int? seed;
  final List<String> stop;
}

/// One request to a text LLM.
@immutable
class LlmRequest {
  /// Purpose: Describe a request. Inputs: `messages`, `sampling`.
  /// Returns: A new request. Side effects: None.
  /// Notes: Content must never be logged by backends or diagnostics.
  const LlmRequest({
    required this.messages,
    this.sampling = const LlmSampling(),
  });

  final List<LlmMessage> messages;
  final LlmSampling sampling;
}

/// Why generation stopped.
enum LlmFinish { stop, length, cancelled }

/// One streamed event.
@immutable
sealed class LlmEvent {
  /// Purpose: Base constructor. Inputs: None. Returns: Event.
  /// Side effects: None. Notes: Sealed; see subclasses.
  const LlmEvent();
}

/// A piece of generated text.
final class LlmDelta extends LlmEvent {
  /// Purpose: Create a delta. Inputs: `text`. Returns: Event.
  /// Side effects: None. Notes: None.
  const LlmDelta(this.text);
  final String text;
}

/// The end of a generation, with measured metrics.
final class LlmDone extends LlmEvent {
  /// Purpose: Create the final event.
  /// Inputs: `finish`; `metrics` measured by the backend.
  /// Returns: Event. Side effects: None.
  /// Notes: Exactly one per successful or cancelled stream.
  const LlmDone(this.finish, [this.metrics = const LlmMetrics()]);
  final LlmFinish finish;
  final LlmMetrics metrics;
}

/// Measured run facts; values are what the runtime reported, never inferred.
@immutable
class LlmMetrics {
  /// Purpose: Describe a run.
  /// Inputs: `device` — actual run location reported by the runtime (such as
  /// `cpu`, `vulkan`, `metal`, `remote`); token counts; timings.
  /// Returns: Metrics. Side effects: None.
  /// Notes: Unknown values are null rather than guessed.
  const LlmMetrics({
    this.device,
    this.promptTokens,
    this.outputTokens,
    this.firstToken,
    this.total,
  });

  final String? device;
  final int? promptTokens;
  final int? outputTokens;
  final Duration? firstToken;
  final Duration? total;

  /// Purpose: Output tokens per second when measurable.
  /// Inputs: None. Returns: `double?`. Side effects: None. Notes: None.
  double? get tokensPerSecond {
    final n = outputTokens;
    final t = total;
    if (n == null || t == null || t.inMicroseconds <= 0) return null;
    return n / (t.inMicroseconds / 1e6);
  }
}

/// Optional abilities a backend declares; nothing is implied by the protocol.
enum LlmAbility { streaming, structuredOutput, tools, vision, embedding }

/// A loaded or loadable text model behind one backend.
abstract class LlmBackend {
  /// Stable backend identifier, such as `llama.cpp` or `online:openai`.
  String get id;

  /// Purpose: Declare optional abilities.
  /// Inputs: None. Returns: Set. Side effects: None.
  /// Notes: Callers must not use undeclared abilities.
  Set<LlmAbility> get abilities;

  /// Purpose: Report readiness of the configured model.
  /// Inputs: None. Returns: `GenAiStatusReport`.
  /// Side effects: May inspect installed files or configuration; never
  /// downloads and never sends user content.
  /// Notes: Never throws.
  Future<GenAiStatusReport> status();

  /// Purpose: Load the model ahead of use.
  /// Inputs: None. Returns: None.
  /// Side effects: Allocates model memory.
  /// Notes: Idempotent; throws [GenAiException] when the model cannot load.
  Future<void> load();

  /// Purpose: Release model memory.
  /// Inputs: None. Returns: None.
  /// Side effects: Frees native resources after running work exits.
  /// Notes: Idempotent.
  Future<void> unload();

  /// Purpose: Generate a streamed reply.
  /// Inputs: `request`.
  /// Returns: Stream of [LlmDelta] events ending with one [LlmDone].
  /// Side effects: Runs inference.
  /// Notes: Errors arrive as [GenAiException] on the stream. Cancelling the
  /// subscription or calling [cancel] stops native work; the backend must not
  /// accept the next request until that work has exited.
  Stream<LlmEvent> generate(LlmRequest request);

  /// Purpose: Stop running generation.
  /// Inputs: None. Returns: Completes after native work has exited.
  /// Side effects: Cancels inference.
  /// Notes: Safe when idle.
  Future<void> cancel();
}

/// Purpose: Collect a stream into text.
/// Inputs: `events`.
/// Returns: `(String text, LlmDone done)`.
/// Side effects: Listens to the stream.
/// Notes: Throws [GenAiException] when the stream ends without [LlmDone].
Future<(String, LlmDone)> collectLlm(Stream<LlmEvent> events) async {
  final buffer = StringBuffer();
  LlmDone? done;
  await for (final e in events) {
    switch (e) {
      case LlmDelta(:final text):
        buffer.write(text);
      case LlmDone():
        done = e;
    }
  }
  if (done == null) {
    throw const GenAiException(GenAiFailure.failed, 'stream ended early');
  }
  return (buffer.toString(), done);
}

/// Exposes an [LlmBackend] through the existing prompt contract so current
/// application generation code can use a local or online model unchanged.
class LlmGenAiBackend extends CapabilityGenAiBackend {
  /// Purpose: Adapt an LLM backend.
  /// Inputs: `llm`; `baseModelName` for diagnostics.
  /// Returns: Adapter. Side effects: None.
  /// Notes: Proofreading stays unsupported: general generation is not the
  /// system proofreading capability. Downloads are not started here; local
  /// model files are managed by the model package from settings.
  LlmGenAiBackend(this.llm, {this.baseModelName});

  final LlmBackend llm;
  final String? baseModelName;

  /// Purpose: Report prompt readiness from the LLM backend.
  /// Inputs: ignored preference flags. Returns: Status. Side effects: Backend status.
  /// Notes: `preferFast` has no meaning for file models.
  @override
  Future<GenAiStatusReport> statusReport({
    bool force = false,
    bool preferFast = false,
  }) => llm.status();

  /// Purpose: Describe the backend for diagnostics.
  /// Inputs: `localeTag` unused. Returns: Info. Side effects: None.
  /// Notes: `platform` carries the backend id.
  @override
  Future<GenAiCoreInfo?> coreInfo({String? localeTag}) async =>
      GenAiCoreInfo(platform: llm.id, installed: true);

  /// Purpose: Refuse in-place downloads.
  /// Inputs: `onProgress`. Returns: Never. Side effects: None.
  /// Notes: Model files download only through model management.
  @override
  Future<bool> download({void Function(int bytes, int total)? onProgress}) =>
      Future.error(const GenAiException(GenAiFailure.unavailable));

  /// Purpose: Generate one answer through the LLM.
  /// Inputs: prompt fields and sampling. Returns: Text. Side effects: Inference.
  /// Notes: `instructions` becomes the system message.
  @override
  Future<String> generate({
    required String instructions,
    required String prompt,
    int maxOutputTokens = 256,
    double temperature = 0,
    int topK = 1,
  }) async {
    final (text, _) = await collectLlm(
      llm.generate(
        LlmRequest(
          messages: [
            if (instructions.isNotEmpty)
              LlmMessage(LlmRole.system, instructions),
            LlmMessage(LlmRole.user, prompt),
          ],
          sampling: LlmSampling(
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topK: topK,
          ),
        ),
      ),
    );
    return text;
  }

  /// Purpose: Choose options by generation plus the validated line parser.
  /// Inputs: prompt fields, options, cap. Returns: ids. Side effects: Inference.
  /// Notes: Same behavior as the Android system path; unparseable replies fail.
  @override
  Future<List<String>> choose({
    required String instructions,
    required String prompt,
    required List<String> options,
    int maxItems = 3,
  }) async {
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

  /// Purpose: Load ahead of a batch. Inputs: None. Returns: None.
  /// Side effects: Loads the model. Notes: Errors are swallowed; advisory.
  @override
  Future<void> prewarm() async {
    try {
      await llm.load();
    } catch (_) {
      // Advisory only; the next request reports the failure.
    }
  }

  /// Purpose: Stop running work. Inputs: None. Returns: After native exit.
  /// Side effects: Cancels inference. Notes: None.
  @override
  Future<void> cancel() => llm.cancel();
}
