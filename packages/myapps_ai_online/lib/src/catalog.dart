/// Purpose: The built-in model catalog: names, context lengths and inputs of
/// the models the templates' providers serve, from a models.dev snapshot.
/// Inputs: Model ids and the template's catalog id.
/// Returns: [OnlineModelCatalog].
/// Side effects: None.
/// Notes: Used until the user refreshes a source's own list, and when a
/// source cannot list its models. Regenerate `catalog.g.dart` with
/// `tool/update_model_catalog.py`; models.dev data is MIT licensed.
library;

import 'package:myapps_ai_core/myapps_ai_core.dart';

import 'http_support.dart';

part 'catalog.g.dart';

/// Lookups into the built-in snapshot.
class OnlineModelCatalog {
  /// Purpose: Prevent instantiation. Inputs: None. Returns: Nothing.
  /// Side effects: None. Notes: Every member is static.
  const OnlineModelCatalog._();

  /// Purpose: Every chat model the snapshot lists for [catalogId].
  /// Inputs: [catalogId], a models.dev provider id. Returns: Entries with
  /// friendly names, sorted by id; empty for an unknown id.
  /// Side effects: None. Notes: None.
  static List<OnlineModelEntry> modelsOf(String catalogId) {
    final provider = _snapshot[catalogId];
    if (provider == null) return const [];
    final (vendor, models) = provider;
    return [for (final e in models.entries) _entry(e.key, vendor, e.value)]
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Purpose: Catalog facts for one model id.
  /// Inputs: [id]; [catalogId] to look in first. Returns: An entry, or null.
  /// Side effects: None.
  /// Notes: Falls back to any provider listing the exact id, then the id
  /// without an `org/` prefix.
  static OnlineModelEntry? lookup(String id, {String? catalogId}) {
    if (_find(id, catalogId) case final hit?) return hit;
    final slash = id.lastIndexOf('/');
    return slash < 0 ? null : _find(id.substring(slash + 1), catalogId);
  }

  /// Purpose: Find [id] in [catalogId], then anywhere. Inputs: [id],
  /// [catalogId]. Returns: Entry or null. Side effects: None.
  /// Notes: Internal; first-party providers win over hosts.
  static OnlineModelEntry? _find(String id, String? catalogId) {
    final first = catalogId == null ? null : _snapshot[catalogId];
    if (first?.$2[id] case final m?) return _entry(id, first!.$1, m);
    OnlineModelEntry? hosted;
    for (final (vendor, models) in _snapshot.values) {
      if (models[id] case final m?) {
        if (vendor != null) return _entry(id, vendor, m);
        hosted ??= _entry(id, null, m);
      }
    }
    return hosted;
  }

  /// Purpose: Build an entry. Inputs: [id], [vendor], [m]. Returns: Entry.
  /// Side effects: None. Notes: Internal. A catalog name already in
  /// `Vendor: Model` form (OpenRouter) is kept; otherwise the vendor comes
  /// from the provider or the id.
  static OnlineModelEntry _entry(
    String id,
    String? vendor,
    (String, int?, String) m,
  ) {
    final (name, context, inputs) = m;
    final who = vendor ?? modelVendorOf(id);
    return OnlineModelEntry(
      id,
      displayName: name.contains(': ') || who == null ? name : '$who: $name',
      vendor: who,
      contextTokens: context,
      inputModalities: inputs.isEmpty ? const [] : inputs.split(','),
    );
  }
}
