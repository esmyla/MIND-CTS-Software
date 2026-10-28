/// lib/features/sensors/presentation/glove_picker.dart
///
/// Pairing UI: choose which glove this app talks to.
///
/// Every patient has their own glove, so the bridge must be told which device
/// to attach to. The bridge will auto-attach when exactly one recognised board
/// is present; this screen covers everything else — two gloves on a bench, an
/// unrecognised board, or a deliberate switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sensor_service.dart';
import '../state/sensor_provider.dart';

/// Opens the picker as a bottom sheet. Returns when the user dismisses it.
Future<void> showGlovePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _GlovePickerSheet(),
  );
}

class _GlovePickerSheet extends ConsumerWidget {
  const _GlovePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final inventoryAsync = ref.watch(gloveInventoryProvider);
    final pairedAsync = ref.watch(pairedGloveProvider);
    final pairedId = pairedAsync.valueOrNull;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Pair a glove',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                ),
                IconButton(
                  tooltip: 'Rescan',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () =>
                      ref.read(sensorServiceProvider).listDevices(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Plug your glove in over USB, then choose it below.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            inventoryAsync.when(
              data: (inv) => _DeviceList(inventory: inv, pairedId: pairedId),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => _Message(
                icon: Icons.link_off_rounded,
                text: 'Cannot reach the sensor bridge. Start it on this '
                    'computer, then tap rescan.',
              ),
            ),

            const SizedBox(height: 8),
            if (pairedId != null)
              TextButton.icon(
                onPressed: () async {
                  await ref.read(pairedGloveProvider.notifier).forget();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Forget this glove'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceList extends ConsumerWidget {
  const _DeviceList({required this.inventory, required this.pairedId});

  final GloveInventory inventory;
  final String? pairedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = inventory.devices;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (devices.isEmpty)
          const _Message(
            icon: Icons.usb_off_rounded,
            text: 'No gloves detected. Check the USB cable, then tap rescan.',
          ),
        ...devices.map((d) => _DeviceTile(
              device: d,
              selected: d.id == pairedId ||
                  (inventory.pairedId != null && d.id == inventory.pairedId),
              onTap: () async {
                await ref.read(pairedGloveProvider.notifier).pair(d.id);
                if (context.mounted) Navigator.pop(context);
              },
            )),
        const Divider(height: 28),
        // Always offered: it is the only way to exercise the UI when no glove
        // is to hand, and it is clearly labelled everywhere it shows up.
        _DeviceTile(
          device: const GloveDevice(
            id: 'simulated-glove',
            port: 'simulated',
            description: 'Simulated glove',
            hasStableId: true,
            likelyGlove: true,
          ),
          selected: inventory.simulated,
          subtitleOverride: 'Synthetic data for demos — not a real measurement',
          onTap: () async {
            await ref.read(pairedGloveProvider.notifier).pair('simulated-glove');
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onTap,
    this.subtitleOverride,
  });

  final GloveDevice device;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final subtitle = subtitleOverride ??
        (device.hasStableId
            ? device.port
            // Worth saying: this pairing is tied to the USB socket, so moving
            // the cable will look like a different glove.
            : '${device.port} · no serial number, pairing is port-based');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? cs.secondaryContainer : cs.surfaceContainerHighest,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          device.isSimulated
              ? Icons.science_rounded
              : selected
                  ? Icons.check_circle_rounded
                  : Icons.usb_rounded,
          color: selected ? cs.onSecondaryContainer : cs.primary,
        ),
        title: Text(device.description,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: selected
            ? Text('Paired',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.w700,
                    ))
            : null,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
