/// Purpose: Provider icons for online sources.
/// Inputs: A template's `iconKey` and a name for the fallback.
/// Returns: [MyAppsProviderIcon], [onlineProviderIconKeys].
/// Side effects: Loads bundled SVG assets.
/// Notes: Icons are LobeHub Icons (MIT), monochrome, tinted with the theme;
/// see `assets/provider_icons/SOURCES.md`. A provider without one shows its
/// initials, so new templates never need an asset.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

/// Icon keys bundled with this package.
const onlineProviderIconKeys = {
  'anthropic', 'azure', 'baidu', 'cerebras', 'cohere', 'deepinfra', //
  'deepseek', 'fireworks', 'gemini', 'github', 'groq', 'huggingface',
  'hunyuan', 'lmstudio', 'minimax', 'mistral', 'moonshot', 'nvidia', //
  'ollama', 'openai', 'openrouter', 'perplexity', 'qwen', 'siliconflow',
  'stepfun', 'together', 'volcengine', 'xai', 'zhipu',
};

/// Purpose: The icon key of a provider record.
/// Inputs: [provider], [templates]. Returns: Its template's key, or null.
/// Side effects: None. Notes: Custom sources have none.
String? onlineProviderIconKey(
  OnlineProvider provider,
  OnlineProviderTemplateRegistry templates,
) => templates.byId(provider.templateId)?.iconKey;

/// A provider's icon, or its initials.
class MyAppsProviderIcon extends StatelessWidget {
  /// Purpose: Bind the icon. Inputs: [iconKey], or null; [name] for the
  /// fallback and semantics; [size]. Returns: Widget. Side effects: None.
  /// Notes: None.
  const MyAppsProviderIcon({
    super.key,
    required this.iconKey,
    required this.name,
    this.size = 24,
  });

  final String? iconKey;
  final String name;
  final double size;

  /// Purpose: Build the icon. Inputs: [context]. Returns: Widget.
  /// Side effects: None. Notes: Tinted with the current icon color.
  @override
  Widget build(BuildContext context) {
    final color =
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    final key = iconKey;
    if (key != null && onlineProviderIconKeys.contains(key)) {
      return SvgPicture.asset(
        'assets/provider_icons/$key.svg',
        package: 'myapps_ai_online_ui',
        width: size,
        height: size,
        semanticsLabel: name,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    final initials = name
        .split(RegExp(r'[\s/._-]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Semantics(
      label: name,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(
            fontSize: size * 0.4,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
