/// Online AI sources: provider configuration and templates, an
/// OpenAI-compatible streaming [LlmBackend], online transcription and privacy
/// notice models. Pure Dart over `package:http`; no native code, no storage.
library;

import 'package:myapps_ai_llm/myapps_ai_llm.dart' show LlmBackend;

export 'src/catalog.dart';
export 'src/controller.dart';
export 'src/http_support.dart';
export 'src/llm_backend.dart';
export 'src/manager.dart';
export 'src/model.dart';
export 'src/privacy_notice.dart';
export 'src/provider.dart';
export 'src/templates.dart';
export 'src/transcription.dart';
