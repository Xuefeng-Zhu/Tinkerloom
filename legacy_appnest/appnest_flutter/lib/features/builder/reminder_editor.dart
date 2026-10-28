import 'package:appnest_spec/appnest_spec.dart';
import 'package:flutter/material.dart';

/// Edits the existing rule, retaining its identity and recipient policy.
class ReminderEditor extends StatefulWidget {
  final AppSpec spec;
  final AutomationSpec rule;
  const ReminderEditor({super.key, required this.spec, required this.rule});

  @override
  State<ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<ReminderEditor> {
  final form = GlobalKey<FormState>();
  late String fieldId = widget.rule.fieldId;
  late final offset = TextEditingController(
    text: (widget.rule.offsetSeconds / 60).toString().replaceFirst(
      RegExp(r'\.0$'),
      '',
    ),
  );

  @override
  void dispose() {
    offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reminder settings'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: fieldId,
                decoration: const InputDecoration(
                  labelText: 'Reminder time field',
                ),
                items: [
                  for (final field
                      in widget.spec
                          .collection(widget.rule.collectionId)
                          .fields)
                    if (field.type == FieldType.timestamp)
                      DropdownMenuItem(
                        value: field.id,
                        child: Text(field.label),
                      ),
                ],
                onChanged: (value) => fieldId = value!,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('reminder-minutes'),
                controller: offset,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Minutes before',
                  helperText: 'Use 0 for the selected time; up to 7 days.',
                ),
                validator: (value) {
                  final minutes = double.tryParse(value ?? '');
                  if (minutes == null ||
                      !minutes.isFinite ||
                      minutes < 0 ||
                      minutes > 10080) {
                    return 'Enter a number from 0 to 10080.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Delivered once to the AppNest inbox. Review and approve this change before using it. Existing records require explicit enrollment.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          final rule = widget.rule.toJson()..remove('id');
          rule['trigger'] = {
            ...rule['trigger'] as Map<String, dynamic>,
            'fieldId': fieldId,
            'offsetSeconds': (double.parse(offset.text) * 60).round(),
          };
          Navigator.pop(context, {
            'type': 'UpdateReminder',
            'ruleId': widget.rule.id,
            'rule': rule,
          });
        },
        child: const Text('Update preview'),
      ),
    ],
  );
}
