/// Privacy notice content and per-device acknowledgement for online sources.
///
/// Applications inject what they send; this package gives the structure and
/// the version check. Persisting the acknowledgement is the application's job
/// and the record must be device-local, never synced or backed up.
library;

import 'package:flutter/foundation.dart';

/// A kind of content an online source may receive.
enum OnlineDataCategory {
  /// Text the user or app writes as a prompt.
  promptText,

  /// A summary derived from app data (for example notes or history).
  appDataSummary,

  /// Recorded or imported audio.
  audio,
}

/// One item the application declares it sends.
@immutable
class OnlineDataItem {
  /// Purpose: Declare sent content.
  /// Inputs: `category`; `description` — app-localized wording, optional.
  /// Returns: Item. Side effects: None.
  /// Notes: The UI words the category when `description` is null.
  const OnlineDataItem(this.category, {this.description});

  /// What kind of content.
  final OnlineDataCategory category;

  /// App-supplied description.
  final String? description;
}

/// When the API key leaves this device.
enum OnlineKeySync {
  /// The key is stored on this device only.
  deviceOnly,

  /// The key syncs through the app's secret channel, only over HTTPS or to a
  /// local, private or trusted endpoint; never in backups or ZIP exports.
  secureEndpointsOnly,
}

/// The content of one online-source privacy notice.
@immutable
class OnlinePrivacyNotice {
  /// Purpose: Describe a notice.
  /// Inputs: `version` — raise when scope or terms change materially;
  /// `recipientHost` — the host requests go to; `providerName`; `sent`;
  /// `keySync`; `usedOnlyWhenSelected` — online use never acts as implicit
  /// fallback (true for every shared backend).
  /// Returns: Notice. Side effects: None.
  /// Notes: Build with [OnlinePrivacyNotice.forProvider] from a configured
  /// provider so the host is never guessed.
  const OnlinePrivacyNotice({
    required this.version,
    required this.recipientHost,
    required this.sent,
    this.providerName,
    this.keySync = OnlineKeySync.secureEndpointsOnly,
    this.usedOnlyWhenSelected = true,
  });

  /// Purpose: Build a notice for a configured provider.
  /// Inputs: `version`; `host` — the provider's recipient host (from
  /// `OnlineProvider.recipientHost`); `providerName`; `sent`; `keySync`.
  /// Returns: Notice, or null when the host is unknown (no notice can be
  /// shown, so the source must stay disabled).
  /// Side effects: None. Notes: None.
  static OnlinePrivacyNotice? forProvider({
    required int version,
    required String? host,
    required List<OnlineDataItem> sent,
    String? providerName,
    OnlineKeySync keySync = OnlineKeySync.secureEndpointsOnly,
  }) => host == null || host.isEmpty
      ? null
      : OnlinePrivacyNotice(
          version: version,
          recipientHost: host,
          providerName: providerName,
          sent: sent,
          keySync: keySync,
        );

  /// Notice version.
  final int version;

  /// Host receiving requests.
  final String recipientHost;

  /// Provider display name.
  final String? providerName;

  /// What is sent.
  final List<OnlineDataItem> sent;

  /// Key sync rule.
  final OnlineKeySync keySync;

  /// Whether the source is used only when explicitly chosen.
  final bool usedOnlyWhenSelected;

  /// Purpose: List the distinct categories sent.
  /// Inputs: None. Returns: Set. Side effects: None. Notes: None.
  Set<OnlineDataCategory> get categories => {for (final s in sent) s.category};
}

/// A device's confirmation of one notice version for one recipient.
@immutable
class OnlinePrivacyAcknowledgement {
  /// Purpose: Create a record.
  /// Inputs: `noticeVersion`; `acknowledgedAt` (normalised to UTC);
  /// `recipientHost` — the host confirmed, null for app-wide records;
  /// `extra` unknown fields.
  /// Returns: Record. Side effects: None.
  /// Notes: Device-local; never a data module.
  OnlinePrivacyAcknowledgement({
    required this.noticeVersion,
    required DateTime acknowledgedAt,
    this.recipientHost,
    Map<String, Object?> extra = const {},
  }) : acknowledgedAt = acknowledgedAt.toUtc(),
       extra = Map.unmodifiable(extra);

  /// Confirmed version.
  final int noticeVersion;

  /// When confirmed, UTC.
  final DateTime acknowledgedAt;

  /// Host confirmed, or null.
  final String? recipientHost;

  /// Unknown fields preserved on write.
  final Map<String, Object?> extra;

  /// Purpose: Parse a stored record.
  /// Inputs: `json`. Returns: Record, or null when missing or malformed.
  /// Side effects: None.
  /// Notes: Malformed reads as absent so the notice is shown again.
  static OnlinePrivacyAcknowledgement? tryParse(Object? json) {
    if (json is! Map) return null;
    final version = json['noticeVersion'];
    final at = json['acknowledgedAt'];
    if (version is! int || at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    final host = json['recipientHost'];
    return OnlinePrivacyAcknowledgement(
      noticeVersion: version,
      acknowledgedAt: parsed,
      recipientHost: host is String ? host : null,
      extra: {
        for (final e in json.entries)
          if (e.key is String &&
              !const {
                'noticeVersion',
                'acknowledgedAt',
                'recipientHost',
              }.contains(e.key))
            e.key as String: e.value,
      },
    );
  }

  /// Purpose: Serialize. Inputs: None. Returns: JSON map with unknown fields.
  /// Side effects: None. Notes: Timestamp as UTC ISO-8601.
  Map<String, Object?> toJson() => {
    ...extra,
    'noticeVersion': noticeVersion,
    'acknowledgedAt': acknowledgedAt.toIso8601String(),
    if (recipientHost != null) 'recipientHost': recipientHost,
  };
}

/// Purpose: Decide whether the user must confirm the notice (again).
/// Inputs: `stored` (null when none); `currentVersion`; optional
/// `recipientHost` — when given, only a record for the same host (case
/// insensitive) counts.
/// Returns: True when nothing is stored, the stored version is older, or the
/// host changed.
/// Side effects: None.
/// Notes: Mirrors MyApps-DATA's WebDAV `needsAcknowledgement`; a newer stored
/// version (after a downgrade) counts as confirmed. Adding or changing an
/// endpoint therefore re-prompts.
bool needsOnlinePrivacyAcknowledgement(
  OnlinePrivacyAcknowledgement? stored,
  int currentVersion, {
  String? recipientHost,
}) =>
    stored == null ||
    stored.noticeVersion < currentVersion ||
    (recipientHost != null &&
        stored.recipientHost?.toLowerCase() != recipientHost.toLowerCase());
