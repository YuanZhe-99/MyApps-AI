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

/// Purpose: Find the directory the llama library was loaded from.
/// Inputs: None.
/// Returns: The directory, or null when the OS will not say.
/// Side effects: Loads the llama library if it was not loaded yet.
/// Notes: ggml's CPU variants are separate libraries beside it on Windows,
/// Android and Linux; ggml would otherwise look beside the executable.
String? llamaLibraryDirectory() {
  final path = _libraryPath();
  return path == null ? null : File(path).parent.path;
}

/// Purpose: The ggml functions, from whichever loaded library exports them.
/// Inputs: None.
/// Returns: The bindings.
/// Side effects: Opens the already-loaded ggml libraries by path.
/// Notes: On Apple ggml is inside llama's own binary; elsewhere it is `ggml`
/// and `ggml-base` beside it.
GgmlBindings ggml() {
  final path = _libraryPath();
  if (path == null) throw StateError('The llama library is not loaded.');
  final dir = File(path).parent.path;
  final names = Platform.isMacOS || Platform.isIOS
      ? [File(path).uri.pathSegments.last]
      : Platform.isWindows
      ? ['ggml.dll', 'ggml-base.dll']
      : Platform.isAndroid
      ? ['libggml.so', 'libggml-base.so']
      : ['libggml.so.0', 'libggml-base.so.0'];
  final libraries = [
    for (final name in names)
      if (File('$dir${Platform.pathSeparator}$name').existsSync())
        DynamicLibrary.open('$dir${Platform.pathSeparator}$name'),
  ];
  if (libraries.isEmpty) {
    throw StateError('None of ${names.join(', ')} is beside $path.');
  }
  return GgmlBindings.fromLookup(<T extends NativeType>(String symbol) {
    for (final library in libraries) {
      if (library.providesSymbol(symbol)) return library.lookup<T>(symbol);
    }
    throw ArgumentError('No library beside $path exports $symbol.');
  });
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
