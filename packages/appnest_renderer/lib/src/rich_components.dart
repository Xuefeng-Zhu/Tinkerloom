part of '../appnest_renderer.dart';

class _RichData {
  final RuntimePage? records;
  final Map<String, dynamic>? aggregate;
  const _RichData({this.records, this.aggregate});
}

/// Build each local boundary independently: adding a 24-hour duration is not a
/// calendar day across daylight-saving changes.
List<Map<String, dynamic>> runtimeDateBuckets(
  DateTime now, {
  String unit = 'day',
  int periods = 30,
}) {
  if (!{'day', 'week', 'month'}.contains(unit) ||
      periods < 1 ||
      periods > 366) {
    throw const SpecException('Choose between 1 and 366 calendar buckets.');
  }
  final day = DateTime(now.year, now.month, now.day);
  final anchor = unit == 'month'
      ? DateTime(day.year, day.month)
      : unit == 'week'
      ? DateTime(day.year, day.month, day.day - day.weekday + 1)
      : day;
  DateTime boundary(int offset) => unit == 'month'
      ? DateTime(anchor.year, anchor.month + offset)
      : DateTime(
          anchor.year,
          anchor.month,
          anchor.day + offset * (unit == 'week' ? 7 : 1),
        );
  return [
    for (var index = 1 - periods; index <= 0; index++)
      _dateBucket(boundary(index), boundary(index + 1)),
  ];
}

Map<String, dynamic> _dateBucket(DateTime start, DateTime end) => {
  'key':
      '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
  'start': start.toUtc().toIso8601String(),
  'end': end.toUtc().toIso8601String(),
};

String _number(Object? value) {
  if (value == null) return 'No data';
  if (value is! num) return '$value';
  if (value is int) return '$value';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  final parts = value.toStringAsPrecision(6).split('e');
  if (parts.first.contains('.')) {
    parts[0] = parts.first
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return parts.join('e');
}

extension _RichComponents on _RichMiniAppRuntimeState {
  Future<_RichData> _loadRichData(
    ViewSpec view,
    Map<String, dynamic> query,
    int retain,
  ) async {
    final stored = state(view), options = view.options;
    if (view.type == 'calendar') {
      final month = stored.month ?? DateTime(now.year, now.month);
      final day = stored.day ?? DateTime(now.year, now.month, now.day);
      final buckets = [
        for (var n = 1; n <= DateTime(month.year, month.month + 1, 0).day; n++)
          _dateBucket(
            DateTime(month.year, month.month, n),
            DateTime(month.year, month.month, n + 1),
          ),
      ];
      final aggregate = await adapter.aggregate(
        view.collectionId,
        {...query}..remove('cursor'),
        {
          'metric': 'count',
          'dateFieldId': options['dateFieldId'],
          'buckets': buckets,
        },
      );
      final records = await _readRecords(view, {
        ...query,
        'filters': [
          ...query['filters'] as List,
          {
            'fieldId': options['dateFieldId'],
            'operator': 'gte',
            'value': day.toUtc().toIso8601String(),
          },
          {
            'fieldId': options['dateFieldId'],
            'operator': 'lt',
            'value': DateTime(
              day.year,
              day.month,
              day.day + 1,
            ).toUtc().toIso8601String(),
          },
        ],
        'sort': [
          {'fieldId': options['dateFieldId'], 'descending': false},
        ],
      }, retain);
      return _RichData(records: records, aggregate: aggregate);
    }
    if (view.type == 'timeline') {
      final records = await _readRecords(view, {
        ...query,
        'filters': [
          ...query['filters'] as List,
          if (stored.undated)
            {
              'fieldId': options['dateFieldId'],
              'operator': 'eq',
              'value': null,
            },
        ],
      }, retain);
      return _RichData(records: records);
    }
    return _RichData(
      aggregate: await adapter.aggregate(
        view.collectionId,
        {...query}..remove('cursor'),
        {
          'metric': options['metric'] ?? 'count',
          if (options['valueFieldId'] != null)
            'fieldId': options['valueFieldId'],
          if (view.groupByFieldId != null) 'groupFieldId': view.groupByFieldId,
          if (options['dateFieldId'] != null) ...{
            'dateFieldId': options['dateFieldId'],
            'buckets': runtimeDateBuckets(
              now,
              unit: options['bucket'] as String? ?? 'day',
              periods: options['periods'] as int? ?? 30,
            ),
          },
        },
      ),
    );
  }

  Widget _richSection(BuildContext context, ViewSpec view) {
    final stored = state(view);
    final editing = _VisualEditScope.of(context) != null;
    final collection = spec.collection(view.collectionId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _recordSectionLabel(spec, view),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: spec.appearance == null ? FontWeight.w700 : null,
          ),
        ),
        const SizedBox(height: 12),
        if (page.primaryActionId == null)
          for (final action
              in view.actionIds
                  .map(spec.action)
                  .where(
                    (a) =>
                        a.capability == 'records.create.v1' &&
                        _permitted(a, null),
                  ))
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _run(action, null, source: view),
                  icon: const Icon(Icons.add),
                  label: Text(action.label),
                ),
              ),
            ),
        if (!editing && _textSearchField(view) != null) ...[
          TextFormField(
            key: ValueKey('search-${view.id}'),
            initialValue: stored.search,
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              stored.search = value;
              stored.records = null;
              _searchTimer?.cancel();
              _searchTimer = Timer(const Duration(milliseconds: 250), _refresh);
            },
          ),
          const SizedBox(height: 12),
        ],
        if (!editing && view.filterFieldIds.isNotEmpty) ...[
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final id in view.filterFieldIds)
                DropdownButton<String>(
                  value: stored.filters[id] ?? '',
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        'All ${collection.field(id).label.toLowerCase()}',
                      ),
                    ),
                    for (final choice in collection.field(id).choices)
                      DropdownMenuItem(value: choice, child: Text(choice)),
                  ],
                  onChanged: (value) {
                    _update(() {
                      stored.records = null;
                      if (value == null || value.isEmpty) {
                        stored.filters.remove(id);
                      } else {
                        stored.filters[id] = value;
                      }
                    });
                    _refresh();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (view.type == 'chart' || view.type == 'metric')
          stored.aggregate == null
              ? const Text('Loading summary…')
              : _aggregateCard(context, view, stored.aggregate!)
        else if (view.type == 'calendar')
          _calendar(context, view)
        else if (view.type == 'timeline') ...[
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Timeline'),
                selected: !stored.undated,
                onSelected: (_) {
                  _update(() {
                    stored.undated = false;
                    stored.records = null;
                  });
                  _refresh();
                },
              ),
              if (!collection
                  .field(view.options['dateFieldId'] as String)
                  .required)
                ChoiceChip(
                  label: const Text('Undated'),
                  selected: stored.undated,
                  onSelected: (_) {
                    _update(() {
                      stored.undated = true;
                      stored.records = null;
                    });
                    _refresh();
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (stored.records != null)
            _timeline(context, view, stored.records!.items)
          else
            const Text('Loading…'),
        ] else if (stored.records == null)
          const Text('Loading…')
        else if (stored.records!.items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No records yet.'),
            ),
          )
        else if (view.type == 'table')
          _table(context, view, stored.records!.items)
        else if (view.type == 'checklist')
          _checklist(context, view, stored.records!.items)
        else
          _imageCollection(context, view, stored.records!.items),
        if (stored.records != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${stored.records!.total} records'),
                if (stored.records!.cursor != null)
                  TextButton(
                    onPressed: () => _refresh(nextView: view.id),
                    child: const Text('Load more'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _table(BuildContext context, ViewSpec view, List<RuntimeItem> items) {
    final collection = spec.collection(view.collectionId), stored = state(view);
    final fields = view.fieldIds.isEmpty
        ? collection.fields
        : view.fieldIds.map(collection.field).toList();
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 640
          ? _tableCards(context, view, items, fields)
          : _desktopTable(context, view, items, fields, stored),
    );
  }

  void _sortTable(ViewSpec view, FieldSpec field, bool descending) {
    _update(() {
      final stored = state(view);
      stored.sortField = field.id;
      stored.descending = descending;
      stored.records = null;
    });
    _refresh();
  }

  Widget _tableCards(
    BuildContext context,
    ViewSpec view,
    List<RuntimeItem> items,
    List<FieldSpec> fields,
  ) {
    final collection = spec.collection(view.collectionId), stored = state(view);
    final titleField = collection.field(
      view.titleFieldId ?? collection.fields.first.id,
    );
    String title(RuntimeItem item) => titleField.type == FieldType.image
        ? 'Image record'
        : '${item.data[titleField.id] ?? 'Untitled'}';
    final sortable = fields.where((field) => field.type != FieldType.image);
    return Column(
      key: ValueKey('mobile-table-${view.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sortable.isNotEmpty) ...[
          Text('Sort by', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final field in sortable)
                Tooltip(
                  message: stored.sortField == field.id
                      ? 'Sort by ${field.label}, ${stored.descending ? 'ascending' : 'descending'}'
                      : 'Sort by ${field.label}, ascending',
                  child: ChoiceChip(
                    selected: stored.sortField == field.id,
                    showCheckmark: false,
                    avatar: stored.sortField == field.id
                        ? Icon(
                            stored.descending
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 18,
                          )
                        : null,
                    label: Text(field.label),
                    onSelected: (_) => _sortTable(
                      view,
                      field,
                      stored.sortField == field.id ? !stored.descending : false,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        for (final item in items)
          Card(
            key: ValueKey('table-record-${view.id}-${item.id}'),
            child: Padding(
              padding: EdgeInsets.all(_space(context, 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _editableField(
                    context,
                    view,
                    titleField.id,
                    Text(
                      title(item),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    pageId: page.id,
                  ),
                  for (final field in fields.where(
                    (field) => field.id != titleField.id,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _editableField(
                        context,
                        view,
                        field.id,
                        field.type == FieldType.image &&
                                item.data[field.id] != null
                            ? _PrivateImage(
                                adapter: adapter,
                                assetId: '${item.data[field.id]}',
                                label: field.label,
                                height: 100,
                              )
                            : Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${field.label}: ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: item.data[field.id] == null
                                          ? 'Not set'
                                          : field.type == FieldType.timestamp
                                          ? _displayDate(
                                              context,
                                              '${item.data[field.id]}',
                                            )
                                          : '${item.data[field.id]}',
                                    ),
                                  ],
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                        pageId: page.id,
                      ),
                    ),
                  if (item.capacity != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: CapacitySummary(item: item),
                    ),
                  if (view.detailPageId != null ||
                      _recordActions(view, item).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (view.detailPageId != null)
                          TextButton.icon(
                            onPressed: _saving || _pendingCommand != null
                                ? null
                                : () => _openRecord(view, item),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text(
                              'Open',
                              semanticsLabel: 'Open ${title(item)}',
                            ),
                          ),
                        for (final action in _recordActions(view, item))
                          OutlinedButton(
                            onPressed: _saving || _pendingCommand != null
                                ? null
                                : () => _run(action, item, source: view),
                            child: Text(
                              _actionLabel(action, item),
                              semanticsLabel:
                                  '${_actionLabel(action, item)} for ${title(item)}',
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _desktopTable(
    BuildContext context,
    ViewSpec view,
    List<RuntimeItem> items,
    List<FieldSpec> fields,
    _ViewState stored,
  ) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: stored.sortField == null
              ? null
              : fields.indexWhere((f) => f.id == stored.sortField),
          sortAscending: !stored.descending,
          dataRowMinHeight: 64,
          dataRowMaxHeight: 104,
          columns: [
            for (final field in fields)
              DataColumn(
                label: Text(field.label),
                numeric: {
                  FieldType.integer,
                  FieldType.number,
                }.contains(field.type),
                onSort: field.type == FieldType.image
                    ? null
                    : (_, ascending) => _sortTable(view, field, !ascending),
              ),
            if (view.detailPageId != null ||
                items.any((r) => _recordActions(view, r).isNotEmpty))
              const DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final item in items)
              DataRow(
                cells: [
                  for (final field in fields)
                    DataCell(
                      SizedBox(
                        width: field.type == FieldType.image ? 80 : 160,
                        child: _editableField(
                          context,
                          view,
                          field.id,
                          field.type == FieldType.image &&
                                  item.data[field.id] != null
                              ? _PrivateImage(
                                  adapter: adapter,
                                  assetId: '${item.data[field.id]}',
                                  label: field.label,
                                  height: 64,
                                )
                              : Text(
                                  item.data[field.id] == null
                                      ? 'Not set'
                                      : field.type == FieldType.timestamp
                                      ? _displayDate(
                                          context,
                                          '${item.data[field.id]}',
                                        )
                                      : '${item.data[field.id]}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          pageId: page.id,
                        ),
                      ),
                      onTap:
                          view.detailPageId == null ||
                              _VisualEditScope.of(context) != null ||
                              _saving ||
                              _pendingCommand != null
                          ? null
                          : () => _navigate(
                              MiniAppLocation(
                                view.detailPageId!,
                                recordId: item.id,
                              ),
                            ),
                    ),
                  if (view.detailPageId != null ||
                      items.any((r) => _recordActions(view, r).isNotEmpty))
                    DataCell(
                      Wrap(
                        spacing: 8,
                        children: [
                          if (view.detailPageId != null)
                            IconButton(
                              tooltip: 'Open record',
                              icon: const Icon(Icons.open_in_new),
                              onPressed: _saving || _pendingCommand != null
                                  ? null
                                  : () => _openRecord(view, item),
                            ),
                          for (final action in _recordActions(view, item))
                            TextButton(
                              onPressed: _saving || _pendingCommand != null
                                  ? null
                                  : () => _run(action, item, source: view),
                              child: Text(action.label),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _openRecord(ViewSpec view, RuntimeItem item) {
    final edit = _VisualEditScope.of(context);
    if (edit != null) {
      edit.onSelect(
        MiniAppEditTarget(MiniAppEditKind.section, view.id, pageId: page.id),
      );
      return;
    }
    if (view.detailPageId != null)
      _navigate(MiniAppLocation(view.detailPageId!, recordId: item.id));
  }

  Widget _calendar(BuildContext context, ViewSpec view) {
    final stored = state(view),
        month = state(view).month ?? DateTime(now.year, now.month);
    final day = stored.day ?? DateTime(now.year, now.month, now.day);
    final counts = {
      for (final group in stored.aggregate?['groups'] as List? ?? [])
        group['key']: group['count'],
    };
    final totalDays = DateTime(month.year, month.month + 1, 0).day;
    final leading = DateTime(month.year, month.month).weekday - 1;
    final locale = MaterialLocalizations.of(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(_space(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _changeMonth(view, -1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    locale.formatMonthYear(month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _changeMonth(view, 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Row(
              children: [
                for (final name in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                  Expanded(child: Center(child: Text(name))),
              ],
            ),
            for (var row = 0; row < ((leading + totalDays) / 7).ceil(); row++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final n = row * 7 + col - leading + 1;
                          if (n < 1 || n > totalDays)
                            return const SizedBox(height: 76);
                          final date = DateTime(month.year, month.month, n);
                          final count =
                              counts[_dateBucket(
                                date,
                                DateTime(month.year, month.month, n + 1),
                              )['key']] ??
                              0;
                          final selected =
                              day.year == date.year &&
                              day.month == date.month &&
                              day.day == n;
                          return Semantics(
                            label:
                                '${locale.formatFullDate(date)}, $count records',
                            selected: selected,
                            button: true,
                            child: InkWell(
                              onTap: () {
                                _update(() {
                                  stored.day = date;
                                  stored.records = null;
                                });
                                _refresh();
                              },
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 76,
                                ),
                                margin: const EdgeInsets.all(1),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                      : null,
                                  borderRadius: BorderRadius.circular(
                                    _radius(context, 8),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text('$n'),
                                    Text(
                                      '$count',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            const Divider(),
            Text(
              locale.formatFullDate(day),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (stored.records == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Loading agenda…'),
              )
            else if (stored.records!.items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No records this day.'),
              )
            else
              for (final item in stored.records!.items)
                _row(context, view, item),
          ],
        ),
      ),
    );
  }

  void _changeMonth(ViewSpec view, int offset) {
    final stored = state(view),
        month = state(view).month ?? DateTime(now.year, now.month);
    _update(() {
      stored.month = DateTime(month.year, month.month + offset);
      stored.day = stored.month;
      stored.records = null;
      stored.aggregate = null;
    });
    _refresh();
  }

  Widget _timeline(
    BuildContext context,
    ViewSpec view,
    List<RuntimeItem> items,
  ) {
    if (items.isEmpty) return const Text('No records in this timeline.');
    final groups = <String, List<RuntimeItem>>{};
    for (final item in items) {
      final value = DateTime.tryParse(
        '${item.data[view.options['dateFieldId']]}',
      )?.toLocal();
      final label = value == null
          ? 'Undated'
          : MaterialLocalizations.of(context).formatFullDate(value);
      groups.putIfAbsent(label, () => []).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final item in group.value) _row(context, view, item),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _aggregateCard(
    BuildContext context,
    ViewSpec view,
    Map<String, dynamic> data,
  ) {
    final value = data['value'] as num?,
        target = view.options['target'] as num?;
    final groups = [
      for (final raw in data['groups'] as List? ?? [])
        Map<String, dynamic>.from(raw),
    ];
    return Card(
      child: Padding(
        padding: EdgeInsets.all(_space(context, 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _number(value),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: spec.appearance == null ? FontWeight.w700 : null,
              ),
            ),
            Text(
              '${view.options['metric'] ?? 'count'} · ${data['total']} matching records',
            ),
            if (target != null) ...[
              const SizedBox(height: 16),
              Text('${_number(value)} of ${_number(target)}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: value == null || target <= 0
                    ? 0
                    : (value / target).clamp(0, 1).toDouble(),
                minHeight: 8,
                semanticsLabel:
                    'Target progress: ${_number(value)} of ${_number(target)}',
              ),
            ],
            if (view.type == 'chart') ...[
              if (view.options['dateFieldId'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'All matching records above. Chart: last ${view.options['periods'] ?? 30} ${view.options['bucket'] ?? 'day'} periods by ${spec.collection(view.collectionId).field(view.options['dateFieldId'] as String).label.toLowerCase()}.',
                  ),
                ),
              const SizedBox(height: 20),
              if (groups.isEmpty)
                const Text('No grouped data.')
              else ...[
                Semantics(
                  label:
                      '${view.label} ${view.options['style']} chart. Values are listed below.',
                  image: true,
                  child: ExcludeSemantics(
                    child: SizedBox(
                      height: 200,
                      child: CustomPaint(
                        painter: _ChartPainter(
                          groups,
                          view.options['style'] as String? ?? 'bar',
                          Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Expose readable values and complete screen-reader values, including small numbers and empty averages.
                Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < groups.length; i++)
                      Semantics(
                        label:
                            '${(groups[i]['key'] == null || groups[i]['key'] == '') ? 'Not set' : groups[i]['key']}: ${groups[i]['value'] ?? 'No data'}',
                        child: ExcludeSemantics(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                color: _chartColor(
                                  Theme.of(context).colorScheme,
                                  i,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${(groups[i]['key'] == null || groups[i]['key'] == '') ? 'Not set' : groups[i]['key']}: ${_number(groups[i]['value'])}',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _imageCollection(
    BuildContext context,
    ViewSpec view,
    List<RuntimeItem> items,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = view.type == 'gallery'
          ? (constraints.maxWidth / 240).floor().clamp(1, 4)
          : (constraints.maxWidth < 700 ? 1 : 2);
      final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: () => _openRecord(view, item),
                      child: _editableField(
                        context,
                        view,
                        view.options['imageFieldId'] as String,
                        _PrivateImage(
                          adapter: adapter,
                          assetId:
                              item.data[view.options['imageFieldId']]
                                  as String?,
                          label:
                              '${item.data[view.options['captionFieldId'] ?? view.titleFieldId] ?? 'Image'}',
                          height: 180,
                        ),
                        pageId: page.id,
                      ),
                    ),
                    _row(context, view, item),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _checklist(
    BuildContext context,
    ViewSpec view,
    List<RuntimeItem> items,
  ) {
    final action = spec.action(view.options['actionId'] as String),
        fieldId = view.options['fieldId'] as String;
    final checked = view.options['checkedValue'] ?? true,
        unchecked = view.options['uncheckedValue'] ?? false;
    return Card(
      child: Column(
        children: [
          for (final item in items)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Checkbox(
                    value: item.data[fieldId] == null
                        ? null
                        : item.data[fieldId] == checked,
                    tristate: true,
                    semanticLabel:
                        '${item.data[view.titleFieldId] ?? 'Record'} complete',
                    onChanged:
                        _saving ||
                            _pendingCommand != null ||
                            !_permitted(action, item)
                        ? null
                        : (_) {
                            final target = item.data[fieldId] == checked
                                ? unchecked
                                : checked;
                            if (action.capability == 'workflow.transition.v1') {
                              final behavior = spec
                                  .collection(view.collectionId)
                                  .behavior(action.behaviorId!);
                              if (!(behavior.transitions[item.data[fieldId]] ??
                                      [])
                                  .contains(target)) {
                                _showFeedback(
                                  'That status transition is not allowed.',
                                );
                                return;
                              }
                            }
                            _execute(
                              action,
                              item,
                              action.capability == 'workflow.transition.v1'
                                  ? {'value': target}
                                  : {
                                      'data': {fieldId: target},
                                    },
                            );
                          },
                  ),
                ),
                Expanded(child: _row(context, view, item)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _movableBoard(
    BuildContext context,
    ViewSpec view,
    List<RuntimeItem> items,
  ) {
    final action = spec.action(view.options['moveActionId'] as String);
    final behavior = spec
        .collection(view.collectionId)
        .behavior(action.behaviorId!);
    final choices = spec
        .collection(view.collectionId)
        .field(view.groupByFieldId!)
        .choices;
    bool canMove(RuntimeItem item, String target) =>
        !_saving &&
        _pendingCommand == null &&
        _VisualEditScope.of(context) == null &&
        _permitted(action, item) &&
        (behavior.transitions[item.data[behavior.fieldId]] ?? []).contains(
          target,
        );
    Widget card(RuntimeItem item) => Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(context, view, item),
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<String>(
              tooltip: 'Move record',
              enabled:
                  !_saving &&
                  _pendingCommand == null &&
                  _VisualEditScope.of(context) == null &&
                  choices.any((c) => canMove(item, c)),
              itemBuilder: (_) => [
                for (final target in choices.where((c) => canMove(item, c)))
                  PopupMenuItem(value: target, child: Text('Move to $target')),
              ],
              onSelected: (target) => _execute(action, item, {'value': target}),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.move_down, size: 18),
                    SizedBox(width: 6),
                    Text('Move'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 700
            ? 1
            : choices.length.clamp(1, 3);
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final choice in choices)
              SizedBox(
                width: width,
                child: DragTarget<RuntimeItem>(
                  onWillAcceptWithDetails: (details) =>
                      canMove(details.data, choice),
                  onAcceptWithDetails: (details) =>
                      _execute(action, details.data, {'value': choice}),
                  builder: (context, candidates, rejected) => Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: candidates.isEmpty
                          ? Theme.of(context).colorScheme.surfaceContainerLow
                          : Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(_radius(context, 12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          choice,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        for (final item in items.where(
                          (r) => r.data[view.groupByFieldId] == choice,
                        ))
                          LongPressDraggable<RuntimeItem>(
                            data: item,
                            maxSimultaneousDrags:
                                choices.any((c) => canMove(item, c)) ? 1 : 0,
                            feedback: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(
                                _radius(context, 12),
                              ),
                              child: SizedBox(
                                width: width,
                                child: Padding(
                                  padding: EdgeInsets.all(_space(context, 20)),
                                  child: Text(
                                    '${item.data[view.titleFieldId] ?? 'Record'}',
                                  ),
                                ),
                              ),
                            ),
                            child: card(item),
                          ),
                        if (!items.any(
                          (r) => r.data[view.groupByFieldId] == choice,
                        ))
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('No records'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _contentSection(BuildContext context, ViewSpec view) {
    if (view.type == 'richText')
      return Card(
        child: Padding(
          padding: EdgeInsets.all(_space(context, 20)),
          child: _FormattedText(view.options['markdown'] as String? ?? ''),
        ),
      );
    final options = view.options;
    final colors = Theme.of(context).colorScheme;
    final background = switch (options['tone']) {
      'success' => colors.tertiaryContainer,
      'warning' => colors.secondaryContainer,
      _ => colors.primaryContainer,
    };
    final foreground = switch (options['tone']) {
      'success' => colors.onTertiaryContainer,
      'warning' => colors.onSecondaryContainer,
      _ => colors.onPrimaryContainer,
    };
    final text = Padding(
      padding: EdgeInsets.all(_space(context, 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            options['title'] as String? ?? view.label,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: spec.appearance == null ? null : foreground),
          ),
          if (options['body'] != null) ...[
            const SizedBox(height: 8),
            Text(
              options['body'] as String,
              style: spec.appearance == null
                  ? null
                  : TextStyle(color: foreground),
            ),
          ],
          if (options['targetPageId'] != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_VisualEditScope.of(context) == null)
                  _navigate(MiniAppLocation(options['targetPageId'] as String));
              },
              child: Text(
                'Open ${spec.page(options['targetPageId'] as String).title}',
              ),
            ),
          ],
        ],
      ),
    );
    return Card(
      color: background,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final assetId = options['imageAssetId'] as String?;
          if (constraints.maxWidth < 640 &&
              assetId == null &&
              options['body'] != null &&
              options['targetPageId'] == null &&
              options['tone'] != 'warning' &&
              _VisualEditScope.of(context) == null) {
            return ExpansionTile(
              key: PageStorageKey('compact-banner-${view.id}'),
              tilePadding: EdgeInsets.symmetric(
                horizontal: _space(context, 16),
                vertical: 4,
              ),
              childrenPadding: EdgeInsets.fromLTRB(
                _space(context, 16),
                0,
                _space(context, 16),
                _space(context, 16),
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              shape: const Border(),
              collapsedShape: const Border(),
              textColor: foreground,
              collapsedTextColor: foreground,
              iconColor: foreground,
              collapsedIconColor: foreground,
              title: Text(
                options['title'] as String? ?? view.label,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: foreground),
              ),
              children: [
                Text(
                  options['body'] as String,
                  style: TextStyle(color: foreground),
                ),
              ],
            );
          }
          final beside =
              options['imagePlacement'] == 'beside' &&
              constraints.maxWidth >= 640 &&
              MediaQuery.textScalerOf(context).scale(100) < 150;
          Widget image() => _PrivateImage(
            adapter: adapter,
            assetId: assetId!,
            label: options['imageAlt'] as String? ?? '',
            height: beside ? 260 : 200,
            thumbnail: false,
          );
          if (assetId != null && beside)
            return Row(
              key: ValueKey('banner-beside-${view.id}'),
              children: [
                Expanded(child: image()),
                Expanded(child: text),
              ],
            );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [if (assetId != null) image(), text],
          );
        },
      ),
    );
  }
}

Color _chartColor(ColorScheme scheme, int index) => [
  scheme.primary,
  scheme.secondary,
  scheme.tertiary,
  scheme.error,
  scheme.primary.withValues(alpha: .6),
  scheme.tertiary.withValues(alpha: .6),
][index % 6];

class _ChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> groups;
  final String style;
  final ColorScheme colors;
  _ChartPainter(this.groups, this.style, this.colors);
  @override
  void paint(Canvas canvas, Size size) {
    final values = groups.map((g) => (g['value'] as num?)?.toDouble()).toList();
    if (values.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    if (style == 'donut') {
      final total = values.fold<double>(0, (a, b) => a + (b ?? 0));
      final rect = Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: math.min(size.width, size.height) * .4,
      );
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(size.width, size.height) * .18;
      if (total <= 0) {
        paint.color = colors.outlineVariant;
        canvas.drawArc(rect, 0, math.pi * 2, false, paint);
        return;
      }
      var start = -math.pi / 2;
      for (var i = 0; i < values.length; i++) {
        final sweep = (values[i] ?? 0) / total * math.pi * 2;
        paint.color = _chartColor(colors, i);
        canvas.drawArc(rect, start, sweep, false, paint);
        start += sweep;
      }
      return;
    }
    final actual = values.whereType<double>();
    final min = actual.fold<double>(0, math.min),
        max = actual.fold<double>(0, math.max);
    final span = max - min == 0 ? 1.0 : max - min;
    double y(double value) => 8 + (max - value) / span * (size.height - 16);
    final zero = y(0), step = size.width / values.length;
    paint
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, zero), Offset(size.width, zero), paint);
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        previous = null;
        continue;
      }
      final point = Offset(step * (i + .5), y(value));
      paint
        ..color = style == 'line' ? colors.primary : _chartColor(colors, i)
        ..strokeWidth = 2;
      if (style == 'line') {
        if (previous != null) canvas.drawLine(previous, point, paint);
        canvas.drawCircle(point, 3, paint);
        previous = point;
      } else {
        canvas.drawRect(
          Rect.fromLTRB(
            step * i + step * .15,
            math.min(zero, point.dy),
            step * (i + 1) - step * .15,
            math.max(zero, point.dy) + (value == 0 ? 1 : 0),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) =>
      oldDelegate.groups != groups ||
      oldDelegate.style != style ||
      oldDelegate.colors != colors;
}

class _PrivateImage extends StatefulWidget {
  final RuntimeAdapter adapter;
  final String? assetId;
  final String label;
  final bool thumbnail;
  final double height;
  const _PrivateImage({
    required this.adapter,
    required this.assetId,
    required this.label,
    this.thumbnail = true,
    this.height = 180,
  });
  @override
  State<_PrivateImage> createState() => _PrivateImageState();
}

class _ImageLoad {
  final Uint8List? bytes;
  const _ImageLoad(this.bytes);
}

class _PrivateImageState extends State<_PrivateImage> {
  Future<_ImageLoad>? _bytes;
  bool _failed = false;
  MemoryImage? _image;
  StreamSubscription<void>? _subscription;
  @override
  void initState() {
    super.initState();
    _read();
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = widget.adapter.watch().listen(
      (_) {
        if (mounted) setState(_read);
      },
      onError: (Object error) {
        if (mounted)
          setState(() {
            _clear();
            _failed = true;
            _bytes = null;
          });
      },
      onDone: () {
        if (mounted)
          setState(() {
            _clear();
            _failed = true;
            _bytes = null;
          });
      },
    );
  }

  void _clear() {
    _image?.evict();
    _image = null;
  }

  void _read() {
    _clear();
    _failed = false;
    _bytes = widget.assetId == null
        ? null
        : Future<Uint8List>.sync(
            () => widget.adapter.readImage(
              widget.assetId!,
              thumbnail: widget.thumbnail,
            ),
          ).then(
            (bytes) => _ImageLoad(bytes),
            onError: (Object error) => const _ImageLoad(null),
          );
  }

  @override
  void didUpdateWidget(covariant _PrivateImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId ||
        oldWidget.adapter != widget.adapter ||
        oldWidget.thumbnail != widget.thumbnail)
      _read();
    if (oldWidget.adapter != widget.adapter) _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: FutureBuilder<_ImageLoad>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data?.bytes != null &&
            !_failed) {
          _image ??= MemoryImage(snapshot.data!.bytes!);
          return Image(
            image: _image!,
            fit: BoxFit.cover,
            width: double.infinity,
            semanticLabel: widget.label,
            errorBuilder: (_, _, _) => _placeholder('Image unavailable'),
          );
        }
        return _placeholder(
          _failed
              ? 'Image unavailable'
              : snapshot.connectionState == ConnectionState.done &&
                    snapshot.data?.bytes == null
              ? widget.adapter.preview &&
                        (widget.assetId?.startsWith('preview_image_') ?? false)
                    ? 'Sample image'
                    : 'Image unavailable'
              : widget.assetId == null
              ? 'No image'
              : 'Loading image…',
        );
      },
    ),
  );
  Widget _placeholder(String label) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              label == 'Sample image'
                  ? Icons.landscape_outlined
                  : Icons.image_outlined,
              size: label == 'Sample image' ? 48 : 24,
              color: Theme.of(context).colorScheme.primary,
            ),
            if (label == 'Sample image') const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

/// Deliberately limited formatted text; never executes HTML or external links.
class _FormattedText extends StatelessWidget {
  final String markdown;
  const _FormattedText(this.markdown);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final line in markdown.split('\n')) _line(context, line)],
  );
  Widget _line(BuildContext context, String raw) {
    final heading = RegExp(r'^(#{1,6})\s+').firstMatch(raw);
    final quote = raw.startsWith('> '),
        bullet = RegExp(r'^(?:[-*]|\d+\.)\s+').hasMatch(raw);
    final text = heading == null
        ? quote
              ? raw.substring(2)
              : raw
        : raw.substring(heading.end);
    final style = heading != null
        ? heading.group(1)!.length <= 2
              ? Theme.of(context).textTheme.headlineSmall
              : Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyMedium;
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)');
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(start, match.start)));
      final token = match.group(0)!;
      spans.add(
        TextSpan(
          text: token.startsWith('**')
              ? token.substring(2, token.length - 2)
              : token.substring(1, token.length - 1),
          style: TextStyle(
            fontWeight: token.startsWith('**') ? FontWeight.w700 : null,
            fontStyle: token.startsWith('*') && !token.startsWith('**')
                ? FontStyle.italic
                : null,
            fontFamily: token.startsWith('`') ? 'monospace' : null,
          ),
        ),
      );
      start = match.end;
    }
    spans.add(TextSpan(text: text.substring(start)));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: quote || bullet ? const EdgeInsets.only(left: 12) : null,
      decoration: quote
          ? BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                  width: 3,
                ),
              ),
            )
          : null,
      child: Text.rich(TextSpan(children: spans), style: style),
    );
  }
}
