/// Purpose: Find where the llama library was loaded from and reach the ggml
/// functions beside it.
/// Inputs: None beyond the loaded libraries.
/// Returns: [llamaLibraryDirectory] and [ggml].
/// Side effects: Calls OS functions through FFI.
/// Notes: Same approach as `myapps_ai_asr_whisper`; nothing is compiled.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../ggml_bindings.g.dart';
import '../llama_bindings.g.dart';

/// Where ggml's libraries are, relative to the loaded llama library.
typedef GgmlLayout = ({
  /// ggml and ggml-base to open: full paths, or sonames on Android.
  List<String> libraries,

  /// Directory for `ggml_backend_load_all_from_path`, or null.
  String? backendDirectory,

  /// CPU backend libraries to choose from by name, for `ggml_backend_load`.
  List<String> cpuVariants,
});

/// The CPU variants of the Android arm64 release (see `native/binaries.json`);
/// [bestCpuVariant] picks among them.
const androidCpuVariants = [
  'libggml-cpu-android_armv9.2_2.so',
  'libggml-cpu-android_armv9.2_1.so',
  'libggml-cpu-android_armv9.0_1.so',
  'libggml-cpu-android_armv8.6_1.so',
  'libggml-cpu-android_armv8.2_2.so',
  'libggml-cpu-android_armv8.2_1.so',
  'libggml-cpu-android_armv8.0_1.so',
];

/// Purpose: Where ggml's libraries are for a llama library at [llamaPath].
/// Inputs: [llamaPath] as the OS reports it; [os] as `Platform.operatingSystem`.
/// Returns: The layout.
/// Side effects: None.
/// Notes: Android maps libraries straight from the APK, so [llamaPath] can be
/// `…/base.apk!/lib/arm64-v8a/libllama.so`: no file or directory exists
/// there. Its libraries are therefore opened by soname, which the app's
/// linker namespace resolves whether or not they were extracted, and its CPU
/// variants are loaded by name instead of by listing a directory.
GgmlLayout ggmlLayout(String llamaPath, {required String os}) {
  final separator = os == 'windows' ? r'\' : '/';
  final dir = llamaPath.substring(0, llamaPath.lastIndexOf(separator));
  return switch (os) {
    'macos' || 'ios' => (
      libraries: [llamaPath],
      backendDirectory: null,
      cpuVariants: const [],
    ),
    'android' => (
      libraries: const ['libggml.so', 'libggml-base.so'],
      backendDirectory: null,
      cpuVariants: androidCpuVariants,
    ),
    'windows' => (
      libraries: ['$dir\\ggml.dll', '$dir\\ggml-base.dll'],
      backendDirectory: dir,
      cpuVariants: const [],
    ),
    _ => (
      libraries: ['$dir/libggml.so.0', '$dir/libggml-base.so.0'],
      backendDirectory: dir,
      cpuVariants: const [],
    ),
  };
}

/// Purpose: The layout for the llama library loaded in this process.
/// Inputs: None.
/// Returns: The layout, or null when the OS will not say where it is.
/// Side effects: Loads the llama library if it was not loaded yet.
/// Notes: None.
GgmlLayout? loadedGgmlLayout() {
  final path = _libraryPath();
  return path == null ? null : ggmlLayout(path, os: Platform.operatingSystem);
}

/// Purpose: The ggml functions, from whichever loaded library exports them.
/// Inputs: None.
/// Returns: The bindings.
/// Side effects: Opens the already-loaded ggml libraries.
/// Notes: Throws [StateError] naming what is missing. On Apple ggml is inside
/// llama's own binary; elsewhere it is `ggml` and `ggml-base` beside it.
GgmlBindings ggml() {
  final layout = loadedGgmlLayout();
  if (layout == null) throw StateError('The llama library is not loaded.');
  final libraries = <DynamicLibrary>[];
  final missing = <String>[];
  for (final name in layout.libraries) {
    try {
      libraries.add(DynamicLibrary.open(name));
    } on ArgumentError {
      missing.add(name);
    }
  }
  if (libraries.isEmpty) {
    throw StateError('Could not open ${missing.join(', ')}.');
  }
  return GgmlBindings.fromLookup(<T extends NativeType>(String symbol) {
    for (final library in libraries) {
      if (library.providesSymbol(symbol)) return library.lookup<T>(symbol);
    }
    throw ArgumentError('No ggml library exports $symbol.');
  });
}

/// Purpose: The CPU variant among [candidates] that ggml rates highest here.
/// Inputs: [candidates], library names the OS linker can find.
/// Returns: The name, or null when none loads or this CPU runs none.
/// Side effects: Opens and closes each candidate.
/// Notes: What `ggml_backend_load_all_from_path` does over a directory: each
/// variant exports `ggml_backend_score`, 0 when this CPU lacks an instruction
/// it was built for, higher for more capable builds. A variant without the
/// function is a single generic build and rates 1.
String? bestCpuVariant(List<String> candidates) {
  String? best;
  var bestScore = 0;
  for (final name in candidates) {
    final DynamicLibrary library;
    try {
      library = DynamicLibrary.open(name);
    } on ArgumentError {
      continue;
    }
    try {
      final score = library.providesSymbol('ggml_backend_score')
          ? library.lookupFunction<Int Function(), int Function()>(
              'ggml_backend_score',
            )()
          : 1;
      if (score > bestScore) (best, bestScore) = (name, score);
    } finally {
      library.close();
    }
  }
  return best;
}

/// Purpose: The file the llama library was loaded from.
/// Inputs: None. Returns: The path, or null.
/// Side effects: Loads the library through its first bound function.
/// Notes: Internal. Asks the OS which module holds `llama_print_system_info`.
String? _libraryPath() {
  final address = Native.addressOf<NativeFunction<Pointer<Char> Function()>>(
    llama_print_system_info,
  );
  if (Platform.isWindows) return _windowsModulePath(address.cast());
  return _dladdrPath(address.cast());
}

/// Purpose: The file a Windows module containing [address] was loaded from.
/// Inputs: [address]. Returns: The path, or null.
/// Side effects: None. Notes: Internal.
String? _windowsModulePath(Pointer<Void> address) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getHandle = kernel32
      .lookupFunction<
        Int32 Function(Uint32, Pointer<Void>, Pointer<Pointer<Void>>),
        int Function(int, Pointer<Void>, Pointer<Pointer<Void>>)
      >('GetModuleHandleExW');
  final getName = kernel32
      .lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Void>, Pointer<Utf16>, int)
      >('GetModuleFileNameW');
  const fromAddress = 0x4, unchangedRefcount = 0x2;
  final module = calloc<Pointer<Void>>();
  final buffer = calloc<Uint16>(32768).cast<Utf16>();
  try {
    if (getHandle(fromAddress | unchangedRefcount, address, module) == 0) {
      return null;
    }
    final length = getName(module.value, buffer, 32768);
    return length == 0 ? null : buffer.toDartString(length: length);
  } finally {
    calloc.free(module);
    calloc.free(buffer);
  }
}

/// `Dl_info`: four pointers on every platform this package ships to.
final class _DlInfo extends Struct {
  external Pointer<Utf8> fileName;
  external Pointer<Void> base;
  external Pointer<Utf8> symbolName;
  external Pointer<Void> symbolAddress;
}

/// Purpose: The shared object containing [address].
/// Inputs: [address]. Returns: The path, or null.
/// Side effects: None. Notes: Internal.
String? _dladdrPath(Pointer<Void> address) {
  final dladdr = DynamicLibrary.process()
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<_DlInfo>),
        int Function(Pointer<Void>, Pointer<_DlInfo>)
      >('dladdr');
  final info = calloc<_DlInfo>();
  try {
    if (dladdr(address, info) == 0 || info.ref.fileName == nullptr) return null;
    return info.ref.fileName.toDartString();
  } finally {
    calloc.free(info);
  }
}
