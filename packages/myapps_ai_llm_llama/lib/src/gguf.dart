/// Purpose: Read a GGUF file's header metadata without llama.cpp, and say
/// whether the pinned build supports its architecture.
/// Inputs: The first bytes of a GGUF file (a local file or an HTTP range).
/// Returns: [GgufHeader], [readGgufHeader], [readGgufHeaderFile],
/// [llamaSupportedArchitectures].
/// Side effects: [readGgufHeaderFile] reads from disk.
/// Notes: Only scalar and string values are kept; arrays (the tokenizer's
/// vocabulary) are skipped. The general keys come first in practice, so a
/// few hundred kilobytes are enough to judge a file before downloading it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

part 'architectures.g.dart';

/// What a GGUF header says about a model.
class GgufHeader {
  /// Purpose: Create a header. Inputs: [version]; [metadata], scalar and
  /// string values by key; [complete], false when the bytes ended before
  /// every key was read. Returns: Header. Side effects: None. Notes: None.
  const GgufHeader({
    required this.version,
    required this.metadata,
    required this.complete,
  });

  /// GGUF format version.
  final int version;

  /// Scalar and string metadata by key.
  final Map<String, Object> metadata;

  /// Whether every key was read.
  final bool complete;

  /// Purpose: `general.architecture`, such as `qwen35` or `gemma4`.
  /// Inputs: None. Returns: Text or null. Side effects: None. Notes: None.
  String? get architecture => _text('general.architecture');

  /// Purpose: `general.name`, such as `Qwen3.5 0.8B`.
  /// Inputs: None. Returns: Text or null. Side effects: None. Notes: None.
  String? get name => _text('general.name');

  /// Purpose: The model's maker, from `general.organization` or
  /// `general.basename`'s owner when present. Inputs: None.
  /// Returns: Text or null. Side effects: None. Notes: None.
  String? get organization => _text('general.organization');

  /// Purpose: Context length the model was trained for.
  /// Inputs: None. Returns: Tokens or null. Side effects: None.
  /// Notes: Read from `<architecture>.context_length`.
  int? get contextLength => switch (metadata['$architecture.context_length']) {
    final int n => n,
    _ => null,
  };

  /// Purpose: Whether the pinned llama.cpp lists this architecture.
  /// Inputs: None. Returns: true, false, or null when the header did not
  /// say. Side effects: None. Notes: Support of an architecture does not
  /// guarantee every variant of it loads.
  bool? get architectureSupported => switch (architecture) {
    final a? => llamaSupportedArchitectures.contains(a),
    null => null,
  };

  /// Purpose: A string value. Inputs: [key]. Returns: Text or null.
  /// Side effects: None. Notes: Internal.
  String? _text(String key) => switch (metadata[key]) {
    final String s when s.trim().isNotEmpty => s.trim(),
    _ => null,
  };
}

/// Purpose: Parse a GGUF header from its first bytes.
/// Inputs: [bytes], at least the start of the file.
/// Returns: The header, or null when the bytes are not GGUF.
/// Side effects: None.
/// Notes: Stops at the end of [bytes] and reports `complete: false`.
GgufHeader? readGgufHeader(Uint8List bytes) {
  final r = _Reader(bytes);
  try {
    if (r.u32() != 0x46554747) return null; // "GGUF", little-endian.
  } on RangeError {
    return null;
  }
  final metadata = <String, Object>{};
  var version = 0;
  try {
    version = r.u32();
    r.u64(); // tensor count
    final count = r.u64();
    for (var i = 0; i < count; i++) {
      final key = r.string();
      final value = r.value(r.u32());
      if (value != null) metadata[key] = value;
    }
  } on RangeError {
    return GgufHeader(version: version, metadata: metadata, complete: false);
  }
  return GgufHeader(version: version, metadata: metadata, complete: true);
}

/// Purpose: Parse the header of a local GGUF file.
/// Inputs: [file]; [maxBytes] to read (8 MiB by default).
/// Returns: The header, or null when it is not GGUF.
/// Side effects: Reads the file. Notes: None.
Future<GgufHeader?> readGgufHeaderFile(
  File file, {
  int maxBytes = 8 << 20,
}) async {
  final raf = await file.open();
  try {
    return readGgufHeader(await raf.read(maxBytes));
  } finally {
    await raf.close();
  }
}

/// Little-endian reader over a byte list.
class _Reader {
  /// Purpose: Bind [bytes]. Inputs: [bytes]. Returns: Reader.
  /// Side effects: None. Notes: Internal.
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  var offset = 0;

  /// Purpose: Advance by [n], throwing at the end. Inputs: [n].
  /// Returns: The previous offset. Side effects: Moves. Notes: Internal.
  int _take(int n) {
    if (offset + n > bytes.length) throw RangeError('end of bytes');
    final at = offset;
    offset += n;
    return at;
  }

  int u32() => data.getUint32(_take(4), Endian.little);
  int u64() => data.getUint64(_take(8), Endian.little);

  String string() {
    final n = u64();
    final at = _take(n);
    return utf8.decode(bytes.sublist(at, at + n), allowMalformed: true);
  }

  /// Purpose: Read a value of GGUF [type]. Inputs: [type].
  /// Returns: int, double, bool or String; null for arrays (skipped).
  /// Side effects: Moves. Notes: Internal; throws on an unknown type.
  Object? value(int type) => switch (type) {
    0 => data.getUint8(_take(1)),
    1 => data.getInt8(_take(1)),
    2 => data.getUint16(_take(2), Endian.little),
    3 => data.getInt16(_take(2), Endian.little),
    4 => u32(),
    5 => data.getInt32(_take(4), Endian.little),
    6 => data.getFloat32(_take(4), Endian.little),
    7 => data.getUint8(_take(1)) != 0,
    8 => string(),
    9 => _skipArray(),
    10 => u64(),
    11 => data.getInt64(_take(8), Endian.little),
    12 => data.getFloat64(_take(8), Endian.little),
    _ => throw RangeError('unknown GGUF type $type'),
  };

  /// Purpose: Skip an array. Inputs: None. Returns: null.
  /// Side effects: Moves. Notes: Internal.
  Object? _skipArray() {
    final type = u32();
    final n = u64();
    const sizes = {
      0: 1,
      1: 1,
      2: 2,
      3: 2,
      4: 4,
      5: 4,
      6: 4,
      7: 1,
      10: 8,
      11: 8,
      12: 8,
    };
    if (sizes[type] case final size?) {
      _take(size * n);
    } else {
      for (var i = 0; i < n; i++) {
        value(type);
      }
    }
    return null;
  }
}
