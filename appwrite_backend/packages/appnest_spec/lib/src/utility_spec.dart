part of '../appnest_spec.dart';

/// Defaults are interpreted at runtime, never inserted into canonical definitions.
class ClockOptions {
  final String style, hourFormat;
  final bool showSeconds, showDate;
  const ClockOptions({
    this.style = 'digital',
    this.hourFormat = 'system',
    this.showSeconds = false,
    this.showDate = true,
  });
  factory ClockOptions.fromJson(Map<String, dynamic> json) {
    keys(json, {
      'style',
      'hourFormat',
      'showSeconds',
      'showDate',
    }, 'clock options');
    final style = json.containsKey('style') ? json['style'] : 'digital';
    final hourFormat = json.containsKey('hourFormat')
        ? json['hourFormat']
        : 'system';
    if (!{'digital', 'analog'}.contains(style) ||
        !{'system', '12', '24'}.contains(hourFormat))
      throw const SpecException(
        'Choose an approved clock style and hour format',
      );
    for (final key in ['showSeconds', 'showDate']) {
      if (json.containsKey(key) && json[key] is! bool)
        throw SpecException('$key must be true or false');
    }
    return ClockOptions(
      style: style,
      hourFormat: hourFormat,
      showSeconds: json['showSeconds'] ?? false,
      showDate: json['showDate'] ?? true,
    );
  }
}

class TimerOptions {
  final int durationMinutes;
  const TimerOptions({this.durationMinutes = 25});
  factory TimerOptions.fromJson(Map<String, dynamic> json) {
    keys(json, {'durationMinutes'}, 'timer options');
    final minutes = json.containsKey('durationMinutes')
        ? json['durationMinutes']
        : 25;
    if (minutes is! int || minutes < 1 || minutes > 180)
      throw const SpecException(
        'Focus duration must be 1 to 180 whole minutes',
      );
    return TimerOptions(durationMinutes: minutes);
  }
}
