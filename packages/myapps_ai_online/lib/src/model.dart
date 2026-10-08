/// Purpose: One model an online source offers.
/// Inputs: JSON stored with its provider record.
/// Returns: [OnlineModel], [OnlineModelOrigin], source-id helpers.
/// Side effects: None.
/// Notes: Record ids match MyTranscribe's `model:<source>:<modelName>`.
library;

import 'package:flutter/foundation.dart';
import 'package:myapps_ai_core/myapps_ai_core.dart';

/// Where a model record came from.
enum OnlineModelOrigin {
  /// The source's template.
  template,

  /// The source's own model list.
  fetched,

  /// Typed by the user.
  manual,
}

const _modelKeys = {
  'modelName',
  'alias',
  'displayName',
  'vendor',
  'contextTokens',
  'inputModalities',
  'origin',
};

/// One enabled model of an online source.
@immutable
class OnlineModel {
  /// Purpose: Describe a model.
  /// Inputs: [modelName], the id the API takes; [alias], the user's name;
  /// [displayName] and [vendor] from the source's list or a catalog;
  /// [contextTokens]; [inputModalities]; [origin]; [extra], unknown fields
  /// kept for newer builds. Returns: Model. Side effects: None.
  /// Notes: None.
  const OnlineModel({
    required this.modelName,
    this.alias,
    this.displayName,
    this.vendor,
    this.contextTokens,
    this.inputModalities = const [],
    this.origin = OnlineModelOrigin.manual,
    this.extra = const {},
  });

  /// API model id, such as `gpt-4o-mini`.
  final String modelName;

  /// The user's name for it; wins over every other name.
  final String? alias;

  /// Name from the source's model list or a catalog, such as
  /// `OpenAI: GPT-4o-mini`.
  final String? displayName;

  /// Maker from a catalog, such as `OpenAI`.
  final String? vendor;

  /// Context length, when known.
  final int? contextTokens;

  /// Accepted inputs such as `text` and `image`, when known.
  final List<String> inputModalities;

  /// Where the record came from.
  final OnlineModelOrigin origin;

  /// Unknown fields, written back unchanged.
  final Map<String, Object?> extra;

  /// Purpose: The model's record id inside [providerId].
  /// Inputs: [providerId]. Returns: `model:<providerId>:<modelName>`.
  /// Side effects: None. Notes: Same form as MyTranscribe's records.
  String recordId(String providerId) => 'model:$providerId:$modelName';

  /// Purpose: The name to show.
  /// Inputs: [vendorHint], usually the source's name, for ids no rule
  /// places. Returns: Alias, else the listed name, else the rule-based
  /// friendly name. Side effects: None. Notes: None.
  String name({String? vendorHint}) {
    if (alias case final a? when a.trim().isNotEmpty) return a.trim();
    if (displayName case final d? when d.trim().isNotEmpty) {
      return d.contains(': ') || vendor == null ? d.trim() : '$vendor: $d';
    }
    return friendlyModelName(modelName, vendor: vendor, vendorHint: vendorHint);
  }

  /// Purpose: Copy with changes. Inputs: Fields to change; [clearAlias].
  /// Returns: Model. Side effects: None. Notes: None.
  OnlineModel copyWith({
    String? alias,
    bool clearAlias = false,
    String? displayName,
    String? vendor,
    int? contextTokens,
    List<String>? inputModalities,
    OnlineModelOrigin? origin,
  }) => OnlineModel(
    modelName: modelName,
    alias: clearAlias ? null : (alias ?? this.alias),
    displayName: displayName ?? this.displayName,
    vendor: vendor ?? this.vendor,
    contextTokens: contextTokens ?? this.contextTokens,
    inputModalities: inputModalities ?? this.inputModalities,
    origin: origin ?? this.origin,
    extra: extra,
  );

  /// Purpose: Serialize. Inputs: None. Returns: JSON map.
  /// Side effects: None. Notes: Unknown fields first, so known ones win.
  Map<String, Object?> toJson() => {
    ...extra,
    'modelName': modelName,
    if (alias != null) 'alias': alias,
    if (displayName != null) 'displayName': displayName,
    if (vendor != null) 'vendor': vendor,
    if (contextTokens != null) 'contextTokens': contextTokens,
    if (inputModalities.isNotEmpty) 'inputModalities': inputModalities,
    'origin': origin.name,
  };

  /// Purpose: Parse. Inputs: [json]. Returns: Model, or null without a
  /// model name. Side effects: None. Notes: Unknown fields are kept.
  static OnlineModel? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['modelName'];
    if (name is! String || name.trim().isEmpty) return null;
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return OnlineModel(
      modelName: name.trim(),
      alias: text(json['alias']),
      displayName: text(json['displayName']),
      vendor: text(json['vendor']),
      contextTokens: switch (json['contextTokens']) {
        final int n when n > 0 => n,
        _ => null,
      },
      inputModalities: [
        if (json['inputModalities'] case final List l)
          for (final m in l)
            if (m is String) m,
      ],
      origin: OnlineModelOrigin.values.firstWhere(
        (o) => o.name == json['origin'],
        orElse: () => OnlineModelOrigin.manual,
      ),
      extra: {
        for (final e in json.entries)
          if (e.key is String && !_modelKeys.contains(e.key))
            e.key as String: e.value,
      },
    );
  }
}

/// Purpose: The source id of one online model, as stored in a selection.
/// Inputs: [providerId], [modelName]. Returns: `online:model:<p>:<m>`.
/// Side effects: None. Notes: Never parsed; matched against known models.
String onlineModelSourceId(String providerId, String modelName) =>
    'online:model:$providerId:$modelName';
