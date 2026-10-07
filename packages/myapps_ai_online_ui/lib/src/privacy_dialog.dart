import 'package:flutter/material.dart';
import 'package:myapps_ai_online/myapps_ai_online.dart';

import 'contracts.dart';

/// Purpose: Show an online privacy notice and ask for confirmation.
/// Inputs: [context], [notice], [labels].
/// Returns: True only when the user confirms; false on decline or dismissal.
/// Side effects: Shows a modal dialog.
/// Notes: Records nothing; the caller stores the acknowledgement.
Future<bool> showOnlinePrivacyNoticeDialog(
  BuildContext context, {
  required OnlinePrivacyNotice notice,
  required MyAppsOnlineLabels labels,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(labels.privacyTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labels.privacyIntro(notice.recipientHost, notice.providerName)),
          const SizedBox(height: 8),
          for (final item in notice.sent)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(child: Text('•  ')),
                  Expanded(child: Text(labels.dataItem(item))),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(labels.keySync(notice.keySync)),
          if (notice.usedOnlyWhenSelected) ...[
            const SizedBox(height: 8),
            Text(labels.onlyWhenSelected),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(labels.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(labels.privacyConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Purpose: Make sure this device has confirmed a provider's notice.
/// Inputs: [context], [controller], [provider], [labels].
/// Returns: True when already confirmed or confirmed now; false when the
/// host is unknown, the user declines, or the context went away.
/// Side effects: May show the notice; stores the acknowledgement on confirm.
/// Notes: Asks again after a notice version bump or a host change.
Future<bool> ensureOnlinePrivacyAcknowledged(
  BuildContext context, {
  required OnlineSourcesController controller,
  required OnlineProvider provider,
  required MyAppsOnlineLabels labels,
  DateTime Function() now = DateTime.now,
}) async {
  final notice = controller.privacyNotice(provider);
  if (notice == null) return false;
  final stored = await controller.acknowledgement(provider.id);
  if (!needsOnlinePrivacyAcknowledgement(
    stored,
    notice.version,
    recipientHost: notice.recipientHost,
  )) {
    return true;
  }
  if (!context.mounted) return false;
  final confirmed = await showOnlinePrivacyNoticeDialog(
    context,
    notice: notice,
    labels: labels,
  );
  if (!confirmed) return false;
  await controller.acknowledge(
    provider.id,
    OnlinePrivacyAcknowledgement(
      noticeVersion: notice.version,
      acknowledgedAt: now(),
      recipientHost: notice.recipientHost,
    ),
  );
  return true;
}
