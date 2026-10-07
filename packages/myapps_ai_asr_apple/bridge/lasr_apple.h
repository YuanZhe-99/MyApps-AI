/*
 * Purpose: The C interface of the Neural Engine bridge (`LasrApple.swift`):
 * FluidAudio's Parakeet v3 behind five plain functions.
 * Inputs: A staged model folder; 16 kHz mono float samples.
 * Returns: A model handle; a JSON result per transcription.
 * Side effects: Loads Core ML models; runs inference.
 * Notes: The Dart bindings are generated from this file by
 * `tool/ffigen.dart`. Every function blocks; call them from a worker isolate.
 * The bridge is built by `.github/workflows/apple-prebuild.yml`, never in the
 * app build (decision D21 of the local-models plan).
 */
#ifndef LASR_APPLE_H
#define LASR_APPLE_H

#include <stdint.h>

/* The bridge's version: FluidAudio's, and the bridge's own revision. */
const char * lasr_apple_version(void);

/* Load a Parakeet v3 Core ML package from `folder`; `cpu_only` keeps it off
 * the Neural Engine. Returns a handle above zero, or zero on failure. */
int64_t lasr_apple_load(const char * folder, int32_t cpu_only);

/* Transcribe `count` samples. Returns JSON — {"text", "tokens": [{"t","s","e"}]}
 * or {"error"} — to be freed with lasr_apple_free. */
char * lasr_apple_transcribe(int64_t handle, const float * samples, int32_t count);

/* Free a string the bridge returned. */
void lasr_apple_free(char * text);

/* Release a loaded model. */
void lasr_apple_release(int64_t handle);

/* The operating system's on-device recogniser (L6): 1 when the device's own
 * language has one. */
int32_t lasr_apple_speech_available(void);

/* Transcribe with the on-device recogniser; `language` empty for the device's
 * own. Asks for permission the first time. Returns JSON as
 * lasr_apple_transcribe does, word times as tokens; free with lasr_apple_free. */
char * lasr_apple_speech_transcribe(const float * samples, int32_t count, const char * language);

#endif
