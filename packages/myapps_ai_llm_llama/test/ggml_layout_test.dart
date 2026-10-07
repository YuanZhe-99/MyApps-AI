import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_llm_llama/src/native/os.dart';

void main() {
  test('Android opens ggml by soname even when llama is inside the APK', () {
    // What dladdr reports when the libraries are mapped from the APK
    // (extractNativeLibs=false): nothing exists at that path.
    const inApk =
        '/data/app/~~x==/com.example-y==/base.apk!/lib/arm64-v8a/libllama.so';
    for (final path in [inApk, '/data/app/com.example/lib/arm64/libllama.so']) {
      final layout = ggmlLayout(path, os: 'android');
      expect(layout.libraries, ['libggml.so', 'libggml-base.so']);
      expect(layout.backendDirectory, isNull);
      expect(layout.cpuVariants, androidCpuVariants);
    }
  });

  test('Android lists every CPU variant of the arm64 release', () {
    expect(androidCpuVariants.toSet(), hasLength(7));
    expect(
      androidCpuVariants,
      everyElement(matches(r'^libggml-cpu-android_armv[0-9.]+_[12]\.so$')),
    );
  });

  test('the best CPU variant is the highest score, skipping missing ones', () {
    final dir = Directory('${Directory.current.path}/.dart_tool/lib');
    final variants = dir.existsSync()
        ? [
            for (final f in dir.listSync())
              if (f.path.contains('libggml-cpu-')) f.path,
          ]
        : <String>[];
    if (variants.isEmpty) {
      markTestSkipped('No desktop CPU variants were built here.');
      return;
    }
    final best = bestCpuVariant(['/nonexistent/libggml-cpu-x.so', ...variants]);
    expect(best, isNotNull);
    expect(variants, contains(best));
  }, testOn: 'linux');

  test('desktop loads beside llama and lists the directory', () {
    final linux = ggmlLayout('/app/lib/libllama.so.0', os: 'linux');
    expect(linux.libraries, [
      '/app/lib/libggml.so.0',
      '/app/lib/libggml-base.so.0',
    ]);
    expect(linux.backendDirectory, '/app/lib');
    expect(linux.cpuVariants, isEmpty);

    final windows = ggmlLayout(r'C:\App\llama.dll', os: 'windows');
    expect(windows.libraries, [r'C:\App\ggml.dll', r'C:\App\ggml-base.dll']);
    expect(windows.backendDirectory, r'C:\App');
  });

  test('Apple finds ggml inside llama itself', () {
    const path = '/App.app/Frameworks/llama.framework/llama';
    final layout = ggmlLayout(path, os: 'macos');
    expect(layout.libraries, [path]);
    expect(layout.backendDirectory, isNull);
  });
}
