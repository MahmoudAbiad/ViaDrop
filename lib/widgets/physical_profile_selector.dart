import 'package:flutter/material.dart';

import '../core/physical_profiles.dart';

/// A shared selector. Disabled entries remain visible with the exact reason
/// from the local device probe. Selecting the same ID on both devices is
/// required; a one-way link cannot negotiate a common mode.
class PhysicalProfileSelector extends StatelessWidget {
  const PhysicalProfileSelector({
    super.key,
    required this.medium,
    required this.capabilities,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
    required this.onRefresh,
    required this.checking,
    this.sending = true,
  });

  final PhysicalMedium medium;
  final PhysicalCapabilities capabilities;
  final String? selectedId;
  final bool enabled;
  final bool sending;
  final bool checking;
  final ValueChanged<String> onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final candidates = physicalProfiles.where((p) => p.medium == medium).toList();
    final selected = selectedId == null ? null : physicalProfileById(selectedId!);
    final current = selected == null ? null : capabilities.availability(selected, sending: sending);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${medium.name}-$selectedId'),
          // ignore: deprecated_member_use
          value: candidates.any((p) => p.id == selectedId &&
              capabilities.availability(p, sending: sending).enabled) ? selectedId : null,
          decoration: const InputDecoration(
            labelText: 'تقنية النقل',
            border: OutlineInputBorder(),
          ),
          hint: const Text('اختر التقنية المدعومة'),
          isExpanded: true,
          items: [
            for (final p in candidates)
              DropdownMenuItem<String>(
                value: p.id,
                enabled: capabilities.availability(p, sending: sending).enabled,
                child: Text(
                  '${p.title}  —  ${capabilities.availability(p, sending: sending).enabled ? 'متاح تجريبياً' : 'معطّل'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: !enabled ? null : (v) {
            if (v != null && capabilities.availability(
                physicalProfileById(v)!, sending: sending).enabled) {
              onChanged(v);
            }
          },
        ),
        const SizedBox(height: 6),
        if (current != null)
          Text(current.reason, style: TextStyle(
            fontSize: 12,
            color: current.enabled ? Theme.of(context).colorScheme.onSurfaceVariant :
                Theme.of(context).colorScheme.error,
          )),
        if (selected != null)
          Text(selected.description,
              style: Theme.of(context).textTheme.bodySmall),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: checking || !enabled ? null : onRefresh,
            icon: checking
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: Text(checking ? 'جارٍ فحص القدرات...' : 'إعادة فحص الجهاز'),
          ),
        ),
        Text(
          'اختر الاسم نفسه على الهاتفين. الفحص محلي مبدئي ولا يضمن نجاح الاتصال '
          'أو جودة الصوت/الكاميرا لدى الجهاز الآخر.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
