import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myapps_ai_llm_llama/myapps_ai_llm_llama.dart';

void main() {
  test('a non-GGUF file has no header', () {
    expect(
      readGgufHeader(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
      isNull,
    );
    expect(readGgufHeader(Uint8List(2)), isNull);
  });

  test('the supported list names the catalog architectures', () {
    expect(
      llamaSupportedArchitectures,
      containsAll(['qwen35', 'gemma4', 'llama']),
    );
    expect(llamaSupportedArchitectures, isNot(contains('(unknown)')));
  });

  for (final path in [
    Platform.environment['LLAMA_TEST_MODEL'],
    '/tmp/opencode/SmolLM2-135M-Instruct-Q4_K_M.gguf',
  ]) {
    test('reads ${path?.split('/').last}', () async {
      final header = (await readGgufHeaderFile(File(path!)))!;
      expect(header.version, greaterThanOrEqualTo(3));
      expect(header.architecture, isNotNull);
      expect(header.architectureSupported, isTrue);
      expect(header.name, isNotNull);
      expect(header.contextLength, greaterThan(0));
      // The first 256 KiB already carry the general keys.
      final head = await File(path)
          .openRead(0, 256 << 10)
          .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d));
      final partial = readGgufHeader(head.takeBytes())!;
      expect(partial.architecture, header.architecture);
      // ignore: avoid_print
      print(
        '${header.architecture} ${header.name} complete=${partial.complete}',
      );
    }, skip: path == null || !File(path).existsSync() ? 'no model' : false);
  }
}
