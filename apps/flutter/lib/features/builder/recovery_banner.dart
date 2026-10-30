import 'package:flutter/material.dart';
import 'package:tinkerloom_client/tinkerloom_client.dart';

bool isRecoveryPermissionDenied(Object issue) =>
    issue is NestError &&
    ({403, 404}.contains(issue.status) ||
        {'forbidden', 'not_found'}.contains(issue.category));

Future<bool> confirmSetAsideRecovery(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set aside this saved request?'),
        content: const Text(
          'The earlier request was saved, but this draft is unavailable. '
          'You can continue with your other apps without opening it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-set-aside-recovery'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set aside'),
          ),
        ],
      ),
    ) ??
    false;

/// An explicit, non-replaying check for a request that outlived its screen.
class PendingBuilderRecoveryBanner extends StatelessWidget {
  const PendingBuilderRecoveryBanner({
    super.key,
    required this.pending,
    required this.checking,
    required this.onCheck,
    this.onSetAside,
  });

  final RetainedBuilderRecovery pending;
  final bool checking;
  final VoidCallback? onCheck;
  final VoidCallback? onSetAside;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xfffff3d7),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          Text(
            onSetAside != null
                ? 'Your earlier request was saved, but its current draft is unavailable.'
                : pending.receiptConfirmed
                ? 'Your earlier change was saved. Check the current draft to finish recovery.'
                : 'An earlier request may have been saved. Check its status before making another change.',
          ),
          if (onCheck != null || checking)
            TextButton.icon(
              key: const ValueKey('check-retained-builder-request'),
              onPressed: checking ? null : onCheck,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(checking ? 'Checking…' : 'Check request'),
            ),
          if (onSetAside != null)
            TextButton(
              key: const ValueKey('set-aside-recovery'),
              onPressed: checking ? null : onSetAside,
              child: const Text('Set aside saved request'),
            ),
        ],
      ),
    ),
  );
}
