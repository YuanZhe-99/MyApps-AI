/// Purpose: Turn raw model ids into OpenRouter-style `Vendor: Model` names,
/// by rule, so new models get readable names without an app update.
/// Inputs: Ids as providers list them (`claude-opus-5-5`, `openai/gpt-4o`,
/// `qwen2.5:7b`, `Llama-3.1-8B-Instruct`), optional catalog facts.
/// Returns: [friendlyModelName], [modelVendorOf].
/// Side effects: None.
/// Notes: Rules, in order: drop an `org/` prefix (kept as a vendor clue), an
/// Ollama `:latest` tag and dates; turn preview/beta/experimental into a
/// suffix; merge adjacent one- or two-digit numbers into a version (`5-5` →
/// `5.5`, `qwen2-5` → `Qwen2.5`); upper-case sizes and short version marks
/// (`8b` → `8B`, `a22b` → `A22B`, `r1` → `R1`; `o3` stays); apply brand
/// casing (GPT, DeepSeek, MiniMax…); keep casing the id already has.
library;

/// Vendors by `org/` prefix as Hugging Face and OpenRouter write them.
const _orgVendors = {
  'openai': 'OpenAI',
  'anthropic': 'Anthropic',
  'google': 'Google',
  'meta-llama': 'Meta',
  'meta': 'Meta',
  'facebook': 'Meta',
  'mistralai': 'Mistral',
  'mistral': 'Mistral',
  'qwen': 'Qwen',
  'alibaba': 'Qwen',
  'deepseek': 'DeepSeek',
  'deepseek-ai': 'DeepSeek',
  'x-ai': 'xAI',
  'xai': 'xAI',
  'moonshotai': 'MoonshotAI',
  'moonshot': 'MoonshotAI',
  'z-ai': 'Z.ai',
  'zai-org': 'Z.ai',
  'zhipuai': 'Z.ai',
  'thudm': 'Z.ai',
  'minimax': 'MiniMax',
  'minimaxai': 'MiniMax',
  'bytedance': 'ByteDance',
  'bytedance-seed': 'ByteDance',
  'baidu': 'Baidu',
  'tencent': 'Tencent',
  'stepfun-ai': 'StepFun',
  'stepfun': 'StepFun',
  'microsoft': 'Microsoft',
  'nvidia': 'NVIDIA',
  'cohere': 'Cohere',
  'coherelabs': 'Cohere',
  'ibm-granite': 'IBM',
  'ibm': 'IBM',
  'amazon': 'Amazon',
  'perplexity': 'Perplexity',
  'liquid': 'Liquid',
  'nousresearch': 'Nous',
  'allenai': 'Ai2',
  'inclusionai': 'inclusionAI',
  'bartowski': '',
  'unsloth': '',
  'lmstudio-community': '',
};

/// Vendors by the leading letters of the model name.
const _prefixVendors = {
  'gpt': 'OpenAI',
  'chatgpt': 'OpenAI',
  'o1': 'OpenAI',
  'o3': 'OpenAI',
  'o4': 'OpenAI',
  'davinci': 'OpenAI',
  'text-embedding': 'OpenAI',
  'whisper': 'OpenAI',
  'dall-e': 'OpenAI',
  'claude': 'Anthropic',
  'gemini': 'Google',
  'gemma': 'Google',
  'qwen': 'Qwen',
  'qwq': 'Qwen',
  'qvq': 'Qwen',
  'deepseek': 'DeepSeek',
  'glm': 'Z.ai',
  'chatglm': 'Z.ai',
  'kimi': 'MoonshotAI',
  'moonshot': 'MoonshotAI',
  'llama': 'Meta',
  'mistral': 'Mistral',
  'mixtral': 'Mistral',
  'ministral': 'Mistral',
  'codestral': 'Mistral',
  'magistral': 'Mistral',
  'devstral': 'Mistral',
  'pixtral': 'Mistral',
  'voxtral': 'Mistral',
  'grok': 'xAI',
  'minimax': 'MiniMax',
  'abab': 'MiniMax',
  'doubao': 'ByteDance',
  'seed': 'ByteDance',
  'ernie': 'Baidu',
  'hunyuan': 'Tencent',
  'step': 'StepFun',
  'phi': 'Microsoft',
  'nemotron': 'NVIDIA',
  'command': 'Cohere',
  'aya': 'Cohere',
  'sonar': 'Perplexity',
  'granite': 'IBM',
  'nova': 'Amazon',
  'smollm': 'Hugging Face',
};

/// Casing of known words; anything else is capitalized.
const _brands = {
  'gpt': 'GPT',
  'chatgpt': 'ChatGPT',
  'glm': 'GLM',
  'chatglm': 'ChatGLM',
  'deepseek': 'DeepSeek',
  'minimax': 'MiniMax',
  'qwen': 'Qwen',
  'qwq': 'QwQ',
  'qvq': 'QVQ',
  'smollm': 'SmolLM',
  'oss': 'OSS',
  'it': 'IT',
  'vl': 'VL',
  'tts': 'TTS',
  'asr': 'ASR',
  'ocr': 'OCR',
  'ai': 'AI',
  'moe': 'MoE',
  'hd': 'HD',
  'api': 'API',
  'gguf': 'GGUF',
  'awq': 'AWQ',
  'gptq': 'GPTQ',
  'fp8': 'FP8',
  'fp16': 'FP16',
  'bf16': 'BF16',
  'f16': 'F16',
  'mlx': 'MLX',
  'qat': 'QAT',
  'dpo': 'DPO',
  'sft': 'SFT',
  'rl': 'RL',
};

/// Suffix words, shown in parentheses at the end.
const _suffixes = {
  'preview': 'Preview',
  'exp': 'Experimental',
  'experimental': 'Experimental',
  'beta': 'Beta',
  'alpha': 'Alpha',
};

final _quant = RegExp(
  r'(?<![a-z0-9])(i?q\d(?:_[0-9a-z]+)+)',
  caseSensitive: false,
);
final _number = RegExp(r'^\d+$');
final _size = RegExp(r'^\d+(?:\.\d+)?[bmkt]$', caseSensitive: false);
final _multiSize = RegExp(r'^\d+x\d+(?:\.\d+)?b$', caseSensitive: false);
final _activeSize = RegExp(r'^[ae]\d+(?:\.\d+)?b$', caseSensitive: false);
final _letterVersion = RegExp(r'^[a-z]\d+(?:\.\d+)*$', caseSensitive: false);
final _leadingLetters = RegExp(r'^([a-z]+)(\d.*)$', caseSensitive: false);

/// Purpose: The vendor of a model id, by `org/` prefix, then by name.
/// Inputs: [id]. Returns: The vendor, or null when unknown.
/// Side effects: None. Notes: A known hosting org (`bartowski`) is no vendor.
String? modelVendorOf(String id) {
  final segments = id.trim().split('/');
  for (final org in segments.take(segments.length - 1).toList().reversed) {
    final vendor = _orgVendors[org.toLowerCase()];
    if (vendor != null && vendor.isNotEmpty) return vendor;
  }
  final base = segments.last.split(':').first.toLowerCase();
  String? best;
  var bestLength = 0;
  for (final e in _prefixVendors.entries) {
    if (base.startsWith(e.key) && e.key.length > bestLength) {
      final next = base.length > e.key.length ? base[e.key.length] : '';
      // `step` must not claim `stepfun-…`'s neighbours like `steps`; a
      // prefix ends at a separator, a digit or the end.
      if (next.isEmpty || RegExp(r'[-_.\d ]').hasMatch(next)) {
        best = e.value;
        bestLength = e.key.length;
      }
    }
  }
  return best;
}

/// Purpose: A user-facing name for a raw model id.
/// Inputs: [id]; [vendor] and [name] from a model catalog, which win;
/// [vendorHint], such as the provider's name, used when no rule finds one.
/// Returns: `Vendor: Name`, or `Name` when no vendor is known.
/// Side effects: None.
/// Notes: Pure and table-driven; see the library notes for the rules.
String friendlyModelName(
  String id, {
  String? vendor,
  String? name,
  String? vendorHint,
}) {
  final who = _nonEmpty(vendor) ?? modelVendorOf(id) ?? _nonEmpty(vendorHint);
  final what = _nonEmpty(name) ?? _nameOf(id);
  return who == null ? what : '$who: $what';
}

/// Purpose: The model part of a friendly name. Inputs: [id]. Returns: Name.
/// Side effects: None. Notes: Internal.
String _nameOf(String id) {
  var base = id.trim().split('/').last;
  final suffixes = <String>[];
  // Ollama tags: `qwen2.5:7b` → size; `:latest` → nothing.
  final colon = base.indexOf(':');
  if (colon > 0) {
    final tag = base.substring(colon + 1);
    base = base.substring(0, colon);
    if (tag.toLowerCase() != 'latest' && tag.isNotEmpty) base = '$base-$tag';
  }
  // Protect quantizations such as q4_k_m from being split on `_`.
  base = base.replaceAllMapped(_quant, (m) => m[1]!.replaceAll('_', '\u0000'));
  var tokens = [
    for (final t in base.split(RegExp(r'[-_ ]+')))
      if (t.isNotEmpty) t.replaceAll('\u0000', '_'),
  ];

  // File names repeat the org: `Qwen_Qwen3.5-0.8B` → `Qwen3.5-0.8B`.
  if (tokens.length > 1 &&
      RegExp(r'^[a-z]+$', caseSensitive: false).hasMatch(tokens[0]) &&
      tokens[1].toLowerCase().startsWith(tokens[0].toLowerCase()) &&
      tokens[1].length > tokens[0].length) {
    tokens.removeAt(0);
  }
  tokens = _dropDates(tokens);
  tokens = [
    for (final t in tokens)
      if (_suffixes[t.toLowerCase()] case final s?)
        () {
          if (!suffixes.contains(s)) suffixes.add(s);
          return null;
        }()
      else if (t.toLowerCase() != 'latest')
        t,
  ].whereType<String>().toList();
  tokens = _mergeVersions(tokens);

  final words = [for (final t in tokens) _case(t)];
  final out = StringBuffer();
  for (var i = 0; i < words.length; i++) {
    if (i > 0) {
      // OpenRouter keeps GPT's hyphen: `GPT-4o Mini`, `GPT-OSS 120B`.
      final previous = words[i - 1];
      out.write(previous == 'GPT' || previous == 'ChatGPT' ? '-' : ' ');
    }
    out.write(words[i]);
  }
  for (final s in suffixes) {
    out.write(' ($s)');
  }
  return out.isEmpty ? id : out.toString();
}

/// Purpose: Remove date stamps. Inputs: [tokens]. Returns: Tokens.
/// Side effects: None. Notes: Internal. Drops `20241022`, `2024-10-22` and
/// a month-day pair such as `05-20` and a trailing month-year such as
/// `03-2025`; keeps four-digit version tags such as `2507` or `0528`.
List<String> _dropDates(List<String> tokens) {
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (_number.hasMatch(t) && t.length == 8 && t.startsWith('20')) continue;
    if (_number.hasMatch(t) &&
        t.length == 4 &&
        t.startsWith('20') &&
        i + 2 < tokens.length &&
        _isMonthDay(tokens[i + 1], tokens[i + 2])) {
      i += 2;
      continue;
    }
    // Month and year: `command-a-03-2025`.
    if (i + 2 == tokens.length &&
        t.length == 2 &&
        (int.tryParse(t) ?? 0) >= 1 &&
        (int.tryParse(t) ?? 13) <= 12 &&
        RegExp(r'^20\d\d$').hasMatch(tokens[i + 1])) {
      break;
    }
    if (i + 1 < tokens.length &&
        tokens[i].length == 2 &&
        _isMonthDay(tokens[i], tokens[i + 1]) &&
        (i + 2 == tokens.length || !_number.hasMatch(tokens[i + 2]))) {
      i += 1;
      continue;
    }
    out.add(t);
  }
  return out;
}

/// Purpose: Whether [m] and [d] read as a two-digit month and day.
/// Inputs: [m], [d]. Returns: bool. Side effects: None. Notes: Internal.
bool _isMonthDay(String m, String d) {
  if (m.length != 2 || d.length != 2) return false;
  final month = int.tryParse(m), day = int.tryParse(d);
  return month != null &&
      day != null &&
      month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= 31;
}

/// Purpose: Join split version numbers. Inputs: [tokens]. Returns: Tokens.
/// Side effects: None. Notes: Internal. Two adjacent one- or two-digit
/// numbers become `a.b` (not three or more, which are ambiguous); a word
/// ending in a digit followed by a one-digit number becomes `word.n`.
List<String> _mergeVersions(List<String> tokens) {
  bool small(String t) => _number.hasMatch(t) && t.length <= 2;
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    final next = i + 1 < tokens.length ? tokens[i + 1] : null;
    final after = i + 2 < tokens.length ? tokens[i + 2] : null;
    final before = out.isEmpty ? null : out.last;
    final run = next != null && small(t) && small(next);
    if (run &&
        (after == null || !small(after)) &&
        (before == null || !small(before))) {
      out.add('$t.$next');
      i++;
      continue;
    }
    if (next != null &&
        !_number.hasMatch(t) &&
        RegExp(r'[a-z]\d+$', caseSensitive: false).hasMatch(t) &&
        _number.hasMatch(next) &&
        next.length == 1 &&
        (after == null || !small(after))) {
      out.add('$t.$next');
      i++;
      continue;
    }
    out.add(t);
  }
  return out;
}

/// Purpose: Case one word. Inputs: [t]. Returns: Word.
/// Side effects: None. Notes: Internal.
String _case(String t) {
  final lower = t.toLowerCase();
  if (_brands[lower] case final b?) return b;
  if (_quant.hasMatch(t) && _quant.firstMatch(t)![0] == t) {
    return t.toUpperCase();
  }
  if (_size.hasMatch(t) || _activeSize.hasMatch(t)) return t.toUpperCase();
  if (_multiSize.hasMatch(t)) return '${lower.substring(0, lower.length - 1)}B';
  if (_letterVersion.hasMatch(t)) {
    return lower.startsWith('o') ? lower : t[0].toUpperCase() + t.substring(1);
  }
  // Keep a word that already has capitals (`DeepSeek`, `Llama`).
  if (t != lower) return t;
  if (_leadingLetters.firstMatch(t) case final m?) {
    final letters = m[1]!.toLowerCase();
    return '${_brands[letters] ?? _capitalize(letters)}${m[2]}';
  }
  if (_number.hasMatch(t) || RegExp(r'^\d').hasMatch(t)) return t;
  return _capitalize(t);
}

/// Purpose: Upper-case the first letter. Inputs: [t]. Returns: Word.
/// Side effects: None. Notes: Internal.
String _capitalize(String t) =>
    t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

/// Purpose: [s] trimmed, or null when empty. Inputs: [s]. Returns: Text.
/// Side effects: None. Notes: Internal.
String? _nonEmpty(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}
