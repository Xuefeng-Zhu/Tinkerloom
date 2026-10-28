part of '../appnest_renderer.dart';

class _UtilityClock extends StatefulWidget {
  final ViewSpec view;
  final DateTime Function() clock;
  const _UtilityClock({super.key, required this.view, required this.clock});
  @override
  State<_UtilityClock> createState() => _UtilityClockState();
}

class _UtilityClockState extends State<_UtilityClock>
    with WidgetsBindingObserver {
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _ticker?.cancel();
    if (state == AppLifecycleState.resumed && mounted) {
      _startTicker();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.view.clockOptions, now = widget.clock().toLocal();
    final localizations = MaterialLocalizations.of(context);
    final use24 =
        options.hourFormat == '24' ||
        options.hourFormat == 'system' &&
            MediaQuery.alwaysUse24HourFormatOf(context);
    var time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(now),
      alwaysUse24HourFormat: use24,
    );
    // A selected 12-hour format must also override locales whose default is 24h.
    if (options.hourFormat == '12') {
      final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final period = now.hour < 12
          ? localizations.anteMeridiemAbbreviation
          : localizations.postMeridiemAbbreviation;
      time =
          '${localizations.formatDecimal(hour)}:${localizations.formatMinute(TimeOfDay.fromDateTime(now))} $period';
    }
    if (options.showSeconds) {
      final seconds = now.second.toString().padLeft(2, '0');
      time = time.replaceFirstMapped(
        RegExp(r'(:\d{2})'),
        (match) => '${match[0]}:$seconds',
      );
    }
    final date = options.showDate ? localizations.formatFullDate(now) : null;
    return Semantics(
      label: '${widget.view.label}: $time${date == null ? '' : ', $date'}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                widget.view.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (options.style == 'analog')
                SizedBox(
                  width: 176,
                  height: 176,
                  child: CustomPaint(
                    key: ValueKey('analog-clock-${widget.view.id}'),
                    painter: _ClockPainter(
                      now,
                      Theme.of(context).colorScheme,
                      showSeconds: options.showSeconds,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  time,
                  key: ValueKey('clock-time-${widget.view.id}'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              if (date != null) Text(date, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  final DateTime now;
  final ColorScheme colors;
  final bool showSeconds;
  const _ClockPainter(this.now, this.colors, {required this.showSeconds});
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), radius = size.shortestSide / 2 - 6;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = colors.surfaceContainerHighest,
    );
    Offset point(double angle, double length) =>
        center + Offset(math.sin(angle), -math.cos(angle)) * length;
    for (var index = 0; index < 12; index++) {
      final angle = index * math.pi / 6;
      canvas.drawLine(
        point(angle, radius - 7),
        point(angle, radius - 13),
        Paint()
          ..color = colors.onSurfaceVariant
          ..strokeWidth = 2,
      );
    }
    void hand(double angle, double length, double width, Color color) =>
        canvas.drawLine(
          center,
          point(angle, length),
          Paint()
            ..color = color
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round,
        );
    hand(
      (now.hour % 12 + now.minute / 60) * math.pi / 6,
      radius * .5,
      5,
      colors.onSurface,
    );
    hand(
      (now.minute + now.second / 60) * math.pi / 30,
      radius * .72,
      3,
      colors.onSurface,
    );
    if (showSeconds)
      hand(now.second * math.pi / 30, radius * .8, 1.5, colors.primary);
    canvas.drawCircle(center, 4, Paint()..color = colors.primary);
  }

  @override
  bool shouldRepaint(_ClockPainter oldDelegate) =>
      now != oldDelegate.now ||
      colors != oldDelegate.colors ||
      showSeconds != oldDelegate.showSeconds;
}

class _UtilityTimer extends StatefulWidget {
  final ViewSpec view;
  final UtilityTimerController controller;
  final bool preview;
  const _UtilityTimer({
    super.key,
    required this.view,
    required this.controller,
    required this.preview,
  });
  @override
  State<_UtilityTimer> createState() => _UtilityTimerWidgetState();
}

class _UtilityTimerWidgetState extends State<_UtilityTimer>
    with WidgetsBindingObserver {
  Timer? _ticker;
  bool _loading = true, _busy = false;
  String? _error;
  int _loadGeneration = 0;
  UtilityTimerController get controller => widget.controller;
  int get minutes => widget.view.timerOptions.durationMinutes;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    _load();
    _startTicker();
  }

  @override
  void didUpdateWidget(_UtilityTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller ||
        oldWidget.view.id != widget.view.id) {
      oldWidget.controller.removeListener(_changed);
      controller.addListener(_changed);
      _load();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await controller.load(widget.view.id, durationMinutes: minutes);
    } catch (_) {
      if (mounted && generation == _loadGeneration)
        _error = 'Could not load this timer. Try again.';
    } finally {
      if (mounted && generation == _loadGeneration)
        setState(() => _loading = false);
    }
  }

  Future<void> _run(
    Future<void> Function(String, {int durationMinutes}) command,
  ) async {
    final edit = _VisualEditScope.of(context);
    if (edit != null) {
      edit.onSelect(MiniAppEditTarget(MiniAppEditKind.section, widget.view.id));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await command(widget.view.id, durationMinutes: minutes);
    } catch (_) {
      if (mounted)
        _error = 'Could not save the timer change. Try the action again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _ticker?.cancel();
    if (state == AppLifecycleState.resumed) {
      _startTicker();
      _changed();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.stateFor(widget.view.id);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (state == null)
      return Column(
        children: [
          Text(_error ?? 'Timer unavailable.'),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Retry timer'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _run(controller.resetSaved),
            child: const Text('Reset saved timer'),
          ),
        ],
      );
    final now = controller.now(), phase = state.phaseAt(now);
    final seconds = (state.remainingAt(now) / 1000).ceil();
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final label = switch (phase) {
      'running' => 'Focusing',
      'paused' => 'Paused',
      'complete' => 'Focus complete',
      _ => 'Ready to focus',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            widget.view.label,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          Semantics(
            label:
                '${widget.view.label}: $label, ${seconds ~/ 60} minutes ${seconds % 60} seconds remaining',
            child: ExcludeSemantics(
              child: Text(
                time,
                key: ValueKey('timer-time-${widget.view.id}'),
                style: Theme.of(context).textTheme.displayMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (phase == 'ready')
                FilledButton(
                  onPressed: _busy ? null : () => _run(controller.start),
                  child: const Text('Start'),
                ),
              if (phase == 'running')
                FilledButton(
                  onPressed: _busy ? null : () => _run(controller.pause),
                  child: const Text('Pause'),
                ),
              if (phase == 'paused')
                FilledButton(
                  onPressed: _busy ? null : () => _run(controller.resume),
                  child: const Text('Resume'),
                ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(controller.reset),
                child: const Text('Reset'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          if (state.durationSeconds != minutes * 60)
            Text(
              'Reset to use your new $minutes minute duration.',
              textAlign: TextAlign.center,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              widget.preview
                  ? 'Preview timer · stays in this preview'
                  : 'On this device · no background alerts',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
