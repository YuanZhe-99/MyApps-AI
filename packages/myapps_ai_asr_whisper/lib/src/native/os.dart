/// Purpose: What the Dart side needs from the operating system to use the
/// prebuilt libraries: where they were loaded from, the ggml functions in
/// them, and how much memory is free.
/// Inputs: None beyond the loaded libraries.
/// Returns: [libraryDirectory], [ggml], [availableMemoryBytes].
/// Side effects: Calls OS functions through FFI.
/// Notes: This replaces the C shim of the source build (decision D21 of the
/// local-models plan): each thing it did natively is done here from Dart.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'ggml_bindings.g.dart';
import 'parakeet_bindings.g.dart';
import 'whisper_bindings.g.dart';

/// Purpose: Find the directory the whisper library was loaded from.
/// Inputs: None.
/// Returns: The directory, or null when the OS will not say.
/// Side effects: Loads the whisper library if it was not loaded yet.
/// Notes: ggml's CPU variants are separate libraries beside it on Windows x64,
/// Android and Linux, and ggml looks beside the executable by default — which
/// is not this folder on Android or in a `flutter test` run.
String? libraryDirectory() {
  final path = _libraryPath();
  if (path == null) return null;
  return File(path).parent.path;
}

/// Purpose: The ggml functions, from whichever loaded library exports them.
/// Inputs: None.
/// Returns: The bindings.
/// Side effects: Opens the already-loaded ggml libraries by path.
/// Notes: On Apple ggml is inside whisper's own binary; elsewhere it is two
/// libraries beside it (`ggml` and `ggml-base`), under the names each
/// platform's set uses. Opening a library that is already loaded returns the
/// same one, so nothing is loaded twice.
GgmlBindings ggml() => GgmlBindings.fromLookup(
  _lookupBeside(
    windows: ['ggml.dll', 'ggml-base.dll'],
    android: ['libggml.so', 'libggml-base.so'],
    linux: ['libggml.so.0', 'libggml-base.so.0'],
  ),
);

/// Purpose: The Parakeet functions, from the library that exports them.
/// Inputs: None.
/// Returns: The bindings.
/// Side effects: Opens the parakeet library beside whisper's.
/// Notes: whisper.cpp's own Parakeet runtime (decision D22 of the
/// local-models plan). On Apple it is inside whisper's binary; elsewhere it is
/// its own library beside whisper's. Throws [StateError] when the binary set
/// has none.
ParakeetBindings parakeet() => ParakeetBindings.fromLookup(
  _lookupBeside(
    windows: ['parakeet.dll'],
    android: ['libparakeet.so'],
    linux: ['libparakeet.so.1'],
  ),
);

/// Purpose: A symbol lookup over libraries beside the whisper library.
/// Inputs: The file names per platform.
/// Returns: A lookup that tries each library in turn.
/// Side effects: Opens the libraries.
/// Notes: Internal helper used within this file only. On Apple every symbol is
/// in whisper's own binary. Opening a library that is already loaded returns
/// the same one, so nothing is loaded twice.
Pointer<T> Function<T extends NativeType>(String) _lookupBeside({
  required List<String> windows,
  required List<String> android,
  required List<String> linux,
}) {
  final path = _libraryPath();
  if (path == null) throw StateError('The whisper library is not loaded.');
  final dir = File(path).parent.path;
  final names = Platform.isMacOS || Platform.isIOS
      ? [File(path).uri.pathSegments.last]
      : Platform.isWindows
      ? windows
      : Platform.isAndroid
      ? android
      : linux;
  final libraries = [
    for (final name in names)
      if (File('$dir${Platform.pathSeparator}$name').existsSync())
        DynamicLibrary.open('$dir${Platform.pathSeparator}$name'),
  ];
  if (libraries.isEmpty) {
    throw StateError('None of ${names.join(', ')} is beside $path.');
  }
  return <T extends NativeType>(String symbol) {
    for (final library in libraries) {
      if (library.providesSymbol(symbol)) return library.lookup<T>(symbol);
    }
    throw ArgumentError('No library beside $path exports $symbol.');
  };
}

/// Purpose: Report how much memory this process could still use.
/// Inputs: None.
/// Returns: Bytes, or null when the platform gives no figure.
/// Side effects: Reads OS counters.
/// Notes: Windows: the available physical memory; Linux and Android:
/// `MemAvailable`; iOS: what the OS will still grant this process; macOS: free
/// plus inactive pages.
int? availableMemoryBytes() {
  try {
    if (Platform.isWindows) return _windowsAvailable();
    if (Platform.isLinux || Platform.isAndroid) return _procMeminfoAvailable();
    if (Platform.isIOS) return _iosAvailable();
    if (Platform.isMacOS) return _macosAvailable();
  } catch (_) {
    return null;
  }
  return null;
}

/// Purpose: The full path of the loaded whisper library.
/// Inputs: None.
/// Returns: The path, or null.
/// Side effects: Loads the library through its first bound function.
/// Notes: Internal helper used within this file only. Asks the OS which
/// module contains the address of `whisper_version`.
String? _libraryPath() {
  final address = Native.addressOf<NativeFunction<Pointer<Char> Function()>>(
    whisper_version,
  );
  if (Platform.isWindows) return _windowsModulePath(address.cast());
  return _dladdrPath(address.cast());
}

// ── Windows ─────────────────────────────────────────────────────────────

final _kernel32 = Platform.isWindows
    ? DynamicLibrary.open('kernel32.dll')
    : null;

/// Purpose: The file a Windows module containing [address] was loaded from.
/// Inputs: [address].
/// Returns: The path, or null.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
String? _windowsModulePath(Pointer<Void> address) {
  final kernel32 = _kernel32!;
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

/// `MEMORYSTATUSEX`.
final class _MemoryStatus extends Struct {
  @Uint32()
  external int length;
  @Uint32()
  external int memoryLoad;
  @Uint64()
  external int totalPhys;
  @Uint64()
  external int availPhys;
  @Uint64()
  external int totalPageFile;
  @Uint64()
  external int availPageFile;
  @Uint64()
  external int totalVirtual;
  @Uint64()
  external int availVirtual;
  @Uint64()
  external int availExtendedVirtual;
}

/// Purpose: The available physical memory on Windows.
/// Inputs: None.
/// Returns: Bytes, or null.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
int? _windowsAvailable() {
  final status = _kernel32!
      .lookupFunction<
        Int32 Function(Pointer<_MemoryStatus>),
        int Function(Pointer<_MemoryStatus>)
      >('GlobalMemoryStatusEx');
  final memory = calloc<_MemoryStatus>();
  try {
    memory.ref.length = sizeOf<_MemoryStatus>();
    return status(memory) == 0 ? null : memory.ref.availPhys;
  } finally {
    calloc.free(memory);
  }
}

// ── POSIX ───────────────────────────────────────────────────────────────

/// `Dl_info`: four pointers on every platform this package ships to.
final class _DlInfo extends Struct {
  external Pointer<Utf8> fileName;
  external Pointer<Void> base;
  external Pointer<Utf8> symbolName;
  external Pointer<Void> symbolAddress;
}

/// Purpose: The file the shared object containing [address] was loaded from.
/// Inputs: [address].
/// Returns: The path, or null.
/// Side effects: None.
/// Notes: Internal helper used within this file only.
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

/// Purpose: `MemAvailable` from `/proc/meminfo`.
/// Inputs: None.
/// Returns: Bytes, or null.
/// Side effects: Reads the file.
/// Notes: Internal helper used within this file only.
int? _procMeminfoAvailable() {
  for (final line in File('/proc/meminfo').readAsLinesSync()) {
    final match = RegExp(r'^MemAvailable:\s+(\d+) kB').firstMatch(line);
    if (match != null) return int.parse(match.group(1)!) * 1024;
  }
  return null;
}

/// Purpose: What iOS will still grant this process.
/// Inputs: None.
/// Returns: Bytes.
/// Side effects: None.
/// Notes: Internal helper used within this file only. `os_proc_available_memory`
/// exists from iOS 13; the app's floor is higher.
int? _iosAvailable() =>
    DynamicLibrary.process().lookupFunction<Size Function(), int Function()>(
      'os_proc_available_memory',
    )();

/// Purpose: Free plus inactive pages on macOS.
/// Inputs: None.
/// Returns: Bytes, or null.
/// Side effects: None.
/// Notes: Internal helper used within this file only. `vm_statistics64` starts
/// with `free_count`, `active_count`, `inactive_count` as 32-bit counters;
/// `HOST_VM_INFO64` is 4 and its count is the struct's size in 32-bit words.
int? _macosAvailable() {
  final process = DynamicLibrary.process();
  final hostSelf = process.lookupFunction<Uint32 Function(), int Function()>(
    'mach_host_self',
  );
  final statistics = process
      .lookupFunction<
        Int32 Function(Uint32, Int32, Pointer<Uint32>, Pointer<Uint32>),
        int Function(int, int, Pointer<Uint32>, Pointer<Uint32>)
      >('host_statistics64');
  final pageSize = process.lookup<UintPtr>('vm_page_size').value;
  const words = 64;
  final stats = calloc<Uint32>(words);
  final count = calloc<Uint32>()..value = 38;
  try {
    if (statistics(hostSelf(), 4, stats, count) != 0) return null;
    return (stats[0] + stats[2]) * pageSize;
  } finally {
    calloc.free(stats);
    calloc.free(count);
  }
}
