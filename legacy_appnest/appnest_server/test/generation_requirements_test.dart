import 'dart:convert';

import 'package:appnest_server/src/modules/builder/generation_requirements.dart';
import 'package:appnest_server/src/modules/builder/provider.dart';
import 'package:appnest_spec/appnest_spec.dart';
import 'package:test/test.dart';

// Frozen public synthetic app183 from the first five-job follow-up.
const _packing183Json = r'''
{
  "actions": [
    {
      "capability": "records.create.v1",
      "collectionId": "packingItems",
      "id": "addItem",
      "label": "Add item"
    },
    {
      "capability": "records.patch.v1",
      "collectionId": "packingItems",
      "id": "editItem",
      "label": "Edit item"
    },
    {
      "behaviorId": "packStatus",
      "capability": "workflow.transition.v1",
      "collectionId": "packingItems",
      "id": "togglePacked",
      "label": "Toggle packed"
    }
  ],
  "appearance": {
    "style": "clean"
  },
  "automationRequests": [],
  "collections": [
    {
      "behaviors": [
        {
          "fieldId": "status",
          "id": "packStatus",
          "transitions": {
            "Packed": [
              "Unpacked"
            ],
            "Unpacked": [
              "Packed"
            ]
          },
          "type": "workflow.v1"
        }
      ],
      "fields": [
        {
          "id": "name",
          "label": "Item Name",
          "required": true,
          "type": "text"
        },
        {
          "choices": [
            "Clothing",
            "Toiletries",
            "Electronics",
            "Documents",
            "Other"
          ],
          "id": "category",
          "label": "Category",
          "required": true,
          "type": "choice"
        },
        {
          "id": "quantity",
          "label": "Quantity",
          "required": true,
          "type": "integer"
        },
        {
          "choices": [
            "Unpacked",
            "Packed"
          ],
          "id": "status",
          "label": "Status",
          "required": true,
          "type": "choice"
        }
      ],
      "id": "packingItems",
      "label": "Packing Items"
    }
  ],
  "formatVersion": 1,
  "icon": "check",
  "name": "Weekend Packing Checklist",
  "navigation": {
    "entryPageId": "listPage",
    "pages": [
      {
        "id": "listPage",
        "primaryActionId": "addItem",
        "title": "Packing List",
        "viewIds": [
          "itemList"
        ]
      },
      {
        "id": "itemDetailsPage",
        "title": "Item Details",
        "viewIds": [
          "itemDetails"
        ]
      },
      {
        "id": "itemFormPage",
        "title": "Edit Item",
        "viewIds": [
          "itemForm"
        ]
      },
      {
        "id": "summaryPage",
        "title": "Summary",
        "viewIds": [
          "packingSummary"
        ]
      }
    ],
    "tabs": [
      {
        "icon": "list",
        "label": "List",
        "pageId": "listPage"
      },
      {
        "icon": "chart",
        "label": "Summary",
        "pageId": "summaryPage"
      }
    ]
  },
  "policyPresetRequest": "personalTracker.v1",
  "requires": [
    "collections.v1",
    "workflow.v1",
    "records.create.v1",
    "records.patch.v1",
    "workflow.transition.v1",
    "views.list.v1",
    "views.form.v1",
    "views.details.v1",
    "views.summary.v1",
    "views.configured.v1",
    "navigation.v1",
    "appearance.v1",
    "views.interactive.v1"
  ],
  "theme": "blue",
  "views": [
    {
      "actionIds": [
        "addItem",
        "editItem",
        "togglePacked"
      ],
      "collectionId": "packingItems",
      "detailPageId": "itemDetailsPage",
      "fieldIds": [
        "category",
        "quantity",
        "status"
      ],
      "filterFieldIds": [
        "category"
      ],
      "formPageId": "itemFormPage",
      "id": "itemList",
      "label": "Packing List",
      "titleFieldId": "name",
      "type": "list"
    },
    {
      "actionIds": [
        "editItem",
        "togglePacked"
      ],
      "collectionId": "packingItems",
      "fieldIds": [
        "category",
        "quantity",
        "status"
      ],
      "formPageId": "itemFormPage",
      "id": "itemDetails",
      "label": "Item Details",
      "titleFieldId": "name",
      "type": "details"
    },
    {
      "actionIds": [
        "addItem",
        "editItem"
      ],
      "collectionId": "packingItems",
      "fieldIds": [
        "name",
        "category",
        "quantity"
      ],
      "id": "itemForm",
      "label": "Item Editor",
      "options": {
        "controls": [
          {
            "control": "text",
            "fieldId": "name"
          },
          {
            "control": "select",
            "fieldId": "category"
          },
          {
            "control": "stepper",
            "fieldId": "quantity",
            "max": 99,
            "min": 1,
            "step": 1
          }
        ]
      },
      "type": "form"
    },
    {
      "actionIds": [],
      "collectionId": "packingItems",
      "groupByFieldId": "status",
      "id": "packingSummary",
      "label": "Packing Summary",
      "type": "summary"
    }
  ]
}
''';

Map<String, dynamic> _reading() =>
    jsonDecode(creationReferenceJson) as Map<String, dynamic>;
AppSpec _spec(Map<String, dynamic> json) => AppSpec.parse(jsonEncode(json));

const _inboxRequest =
    'Build a personal reminders app with open and completed items, optional due '
    'dates, and a separate optional reminder time for my AppNest inbox.';
const _potluckRequest =
    'Help me organize a neighborhood potluck. I want everyone to add their dish, '
    'how many it serves, any allergy notes, and whether it is planned, confirmed '
    'or delivered. Show me a dish list and a progress summary.';

Map<String, dynamic> _ownerReminders() {
  final json = _reading();
  json['collections'][0]['fields'][1]['choices'] = ['Open', 'Completed'];
  json['collections'][0]['behaviors'][0]['transitions'] = {
    'Open': ['Completed'],
    'Completed': ['Open'],
  };
  json['collections'][0]['fields'].addAll([
    {
      'id': 'targetMoment',
      'label': 'Target',
      'type': 'timestamp',
      'required': false,
    },
    {
      'id': 'nudgeMoment',
      'label': 'Ping',
      'type': 'timestamp',
      'required': false,
    },
  ]);
  json['views'][2]['fieldIds'] = ['title', 'targetMoment', 'nudgeMoment'];
  json['requires'].addAll([
    'notifications.inApp.v1',
    'notifications.owner.v1',
    'automations.conditions.v1',
  ]);
  json['automationRequests'] = <dynamic>[
    {
      'id': 'scheduledPing',
      'trigger': {
        'type': 'beforeTimestamp',
        'collectionId': 'books',
        'fieldId': 'nudgeMoment',
        'offsetSeconds': 0,
      },
      'effect': {'type': 'notifyOwner', 'channel': 'inApp'},
      'condition': {'fieldId': 'status', 'value': 'Open'},
    },
  ];
  return json;
}

// Frozen public synthetic app186 from the separate v16 Packing job.
const _packing186Json = r'''
{
  "actions": [
    {
      "capability": "records.create.v1",
      "collectionId": "items",
      "id": "addItem",
      "label": "Add item"
    },
    {
      "capability": "records.patch.v1",
      "collectionId": "items",
      "id": "editItem",
      "label": "Edit item"
    }
  ],
  "appearance": {
    "style": "clean"
  },
  "automationRequests": [],
  "collections": [
    {
      "behaviors": [],
      "fields": [
        {
          "id": "name",
          "label": "Name",
          "required": true,
          "type": "text"
        },
        {
          "choices": [
            "Clothing",
            "Toiletries",
            "Electronics",
            "Documents",
            "Other"
          ],
          "id": "category",
          "label": "Category",
          "required": true,
          "type": "choice"
        },
        {
          "id": "quantity",
          "label": "Quantity",
          "required": true,
          "type": "integer"
        },
        {
          "id": "packed",
          "label": "Packed",
          "required": false,
          "type": "boolean"
        }
      ],
      "id": "items",
      "label": "Items"
    }
  ],
  "formatVersion": 1,
  "icon": "check",
  "name": "Weekend Packing Checklist",
  "navigation": {
    "entryPageId": "itemsPage",
    "pages": [
      {
        "id": "itemsPage",
        "primaryActionId": "addItem",
        "title": "Packing List",
        "viewIds": [
          "itemList"
        ]
      },
      {
        "id": "itemDetailsPage",
        "title": "Item Details",
        "viewIds": [
          "itemDetails"
        ]
      },
      {
        "id": "itemFormPage",
        "title": "Add/Edit Item",
        "viewIds": [
          "itemForm"
        ]
      },
      {
        "id": "checklistPage",
        "title": "Checklist",
        "viewIds": [
          "packingChecklist"
        ]
      },
      {
        "id": "summaryPage",
        "title": "Summary",
        "viewIds": [
          "packedCount",
          "unpackedCount"
        ]
      }
    ],
    "tabs": [
      {
        "icon": "list",
        "label": "List",
        "pageId": "itemsPage"
      },
      {
        "icon": "check",
        "label": "Checklist",
        "pageId": "checklistPage"
      },
      {
        "icon": "chart",
        "label": "Summary",
        "pageId": "summaryPage"
      }
    ]
  },
  "policyPresetRequest": "personalTracker.v1",
  "requires": [
    "collections.v1",
    "views.list.v1",
    "views.details.v1",
    "views.form.v1",
    "views.checklist.v1",
    "views.metric.v1",
    "records.create.v1",
    "records.patch.v1",
    "navigation.v1",
    "views.configured.v1",
    "appearance.v1"
  ],
  "theme": "teal",
  "views": [
    {
      "actionIds": [
        "addItem",
        "editItem"
      ],
      "collectionId": "items",
      "detailPageId": "itemDetailsPage",
      "fieldIds": [
        "category",
        "quantity",
        "packed"
      ],
      "filterFieldIds": [
        "category"
      ],
      "formPageId": "itemFormPage",
      "id": "itemList",
      "label": "Items",
      "titleFieldId": "name",
      "type": "list"
    },
    {
      "actionIds": [
        "editItem"
      ],
      "collectionId": "items",
      "fieldIds": [
        "category",
        "quantity",
        "packed"
      ],
      "formPageId": "itemFormPage",
      "id": "itemDetails",
      "label": "Item",
      "titleFieldId": "name",
      "type": "details"
    },
    {
      "actionIds": [
        "addItem",
        "editItem"
      ],
      "collectionId": "items",
      "fieldIds": [
        "name",
        "category",
        "quantity"
      ],
      "id": "itemForm",
      "label": "Item",
      "type": "form"
    },
    {
      "actionIds": [
        "editItem"
      ],
      "collectionId": "items",
      "fieldIds": [
        "category",
        "quantity"
      ],
      "id": "packingChecklist",
      "label": "Packing Checklist",
      "options": {
        "actionId": "editItem",
        "fieldId": "packed"
      },
      "titleFieldId": "name",
      "type": "checklist"
    },
    {
      "actionIds": [],
      "collectionId": "items",
      "id": "packedCount",
      "label": "Packed",
      "options": {
        "metric": "count"
      },
      "query": {
        "filters": [
          {
            "fieldId": "packed",
            "operator": "eq",
            "value": true
          }
        ]
      },
      "type": "metric"
    },
    {
      "actionIds": [],
      "collectionId": "items",
      "id": "unpackedCount",
      "label": "Unpacked",
      "options": {
        "metric": "count"
      },
      "query": {
        "filters": [
          {
            "fieldId": "packed",
            "operator": "eq",
            "value": false
          }
        ]
      },
      "type": "metric"
    }
  ]
}
''';

void main() {
  final mismatch = throwsA(isA<SpecException>());

  const packingRequest =
      'Build a packing checklist for my weekend trip. '
      'Each item needs a name, category, quantity and a packed checkbox. '
      'Let me tick items as I pack, search by item name, and see a count of packed and unpacked items.';

  Map<String, dynamic> workflowCheckbox() {
    final json = jsonDecode(_packing183Json) as Map<String, dynamic>;
    json['views'][0]['type'] = 'checklist';
    json['views'][0]['options'] = {
      'fieldId': 'status',
      'actionId': 'togglePacked',
      'checkedValue': 'Packed',
      'uncheckedValue': 'Unpacked',
    };
    json['requires'].add('views.checklist.v1');
    return json;
  }

  Map<String, dynamic> booleanCheckbox() {
    final json = workflowCheckbox();
    json['collections'][0]['fields'][3] = {
      'id': 'packedFlag',
      'label': 'Packed',
      'type': 'boolean',
      'required': true,
    };
    json['collections'][0]['behaviors'] = [];
    json['actions'].removeLast();
    for (final view in json['views'] as List) {
      (view['actionIds'] as List).remove('togglePacked');
      view['fieldIds'] = (view['fieldIds'] as List? ?? [])
          .map((id) => id == 'status' ? 'packedFlag' : id)
          .toList();
    }
    json['views'][0]['options'] = {
      'fieldId': 'packedFlag',
      'actionId': 'editItem',
    };
    json['views'][2]['fieldIds'].add('packedFlag');
    json['views'][2]['options']['controls'].add({
      'fieldId': 'packedFlag',
      'control': 'checkbox',
    });
    json['views'][3] = {
      'id': 'packingSummary',
      'type': 'metric',
      'label': 'Packed',
      'collectionId': 'packingItems',
      'options': {'metric': 'count'},
      'query': {
        'filters': [
          {'fieldId': 'packedFlag', 'operator': 'eq', 'value': true},
        ],
      },
    };
    json['requires'].add('views.metric.v1');
    return json;
  }

  test('exact packing183 candidate cannot replace an explicit checkbox with a status menu', () {
    final requirements = GenerationRequirements.fromRequest(packingRequest);
    expect(requirements.toJson(), {
      'recordCheckboxes': [
        {
          'label': 'packed',
          'reachableChecklist': true,
          'requireBinaryInitialization': true,
        },
      ],
    });
    final original = AppSpec.parse(_packing183Json);
    expect(
      original.hash,
      'dbe8e15012d1bbd0dee35f1e06d7f138925faa6e4e584b57fe2eee192c746d11',
    );
    expect(
      () => requirements.validate(original),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'missing tick route',
          contains('reachable packed checklist checkbox'),
        ),
      ),
    );
    // Validation does not mutate that historic candidate or its hash.
    expect(AppSpec.parse(_packing183Json).hash, original.hash);
    final request = buildAiRequest(
      'test',
      packingRequest,
      _spec(_reading()),
      editing: false,
    );
    expect(
      (jsonDecode(request['messages'].last['content'] as String)
          as Map)['explicitRequirements'],
      requirements.toJson(),
    );
  });

  test('exact packing186 candidate cannot leave new checkbox values unset', () {
    final requirements = GenerationRequirements.fromRequest(packingRequest);
    final original = AppSpec.parse(_packing186Json);
    expect(
      original.hash,
      'a1789cb85cb62b2e9e602cd43d650594d3bb7810dbf381a0a22c104da31aa9e5',
    );
    expect(original.collection('items').field('packed').required, isFalse);
    expect(original.view('itemForm').fieldIds, isNot(contains('packed')));
    // The actual form's input survives normalization without a false default,
    // so neither true nor false equality counts it before the first toggle.
    final input = {
      'name': 'Cedar socks',
      'category': 'Clothing',
      'quantity': 3,
    };
    expect(original.collection('items').normalizeRecord(input), input);
    expect(
      () => requirements.validate(original),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'binary initialization diagnostic',
          allOf(
            contains('required boolean field'),
            contains('create/edit form'),
          ),
        ),
      ),
    );
    expect(AppSpec.parse(_packing186Json).hash, original.hash);
  });

  test('binary checkbox needs a required field and an actual reachable creation form', () {
    final requirements = GenerationRequirements.fromRequest(packingRequest);
    Map<String, dynamic> binary() {
      final json = jsonDecode(_packing186Json) as Map<String, dynamic>;
      json['collections'][0]['fields'][3]['required'] = true;
      json['views'][2]['fieldIds'].add('packed');
      return json;
    }

    final initialized = _spec(binary());
    expect(() => requirements.validate(initialized), returnsNormally);
    expect(initialized.collection('items').field('packed').required, isTrue);
    expect(initialized.view('itemForm').fieldIds, contains('packed'));
    expect(
      () => initialized.collection('items').normalizeRecord({
        'name': 'Cedar socks',
        'category': 'Clothing',
        'quantity': 3,
      }),
      mismatch,
    );
    // A visible but nullable field still permits the uncounted third state.
    final nullable = binary();
    nullable['collections'][0]['fields'][3]['required'] = false;
    expect(() => requirements.validate(_spec(nullable)), mismatch);
    // Every form declares create; that alone cannot prove a visible add route.
    final editOnly = binary();
    editOnly['views'][0]['actionIds'] = ['editItem'];
    editOnly['navigation']['pages'][0].remove('primaryActionId');
    expect(() => requirements.validate(_spec(editOnly)), mismatch);
    // Empty fieldIds means all fields and initializes the required checkbox.
    final allFields = binary();
    allFields['views'][2].remove('fieldIds');
    expect(() => requirements.validate(_spec(allFields)), returnsNormally);
  });

  test('explicit optional checkbox keeps its UI requirement without requiring binary initialization', () {
    for (final request in [
      'Save Packed (optional checkbox).',
      'Add an optional packed checkbox.',
    ]) {
      final requirements = GenerationRequirements.fromRequest(request);
      expect(
        requirements.recordCheckboxes.single.label.toLowerCase(),
        'packed',
      );
      expect(
        requirements.recordCheckboxes.single.requireBinaryInitialization,
        isFalse,
      );
      expect(
        () => requirements.validate(AppSpec.parse(_packing186Json)),
        returnsNormally,
      );
      expect(
        () => requirements.validate(AppSpec.parse(_packing183Json)),
        mismatch,
      );
    }
    for (final request in [
      'Do not add Packed (optional checkbox).',
      'The phrase "Packed (optional checkbox)" is documentation.',
      'Add Packed (required checkbox) and Packed (optional checkbox).',
      'Add a required packed checkbox. Show the packed checkbox (optional).',
      'Add a packed checkbox that is required. Add Packed (optional checkbox).',
    ]) {
      expect(
        GenerationRequirements.fromRequest(request).recordCheckboxes,
        isEmpty,
      );
    }
  });

  test(
    'parenthesized optional checkbox suffix preserves the UI requirement',
    () {
      final requirements = GenerationRequirements.fromRequest(
        'Add a packed checkbox (optional).',
      );
      expect(requirements.recordCheckboxes.single.label, 'packed');
      expect(
        requirements.recordCheckboxes.single.requireBinaryInitialization,
        isFalse,
      );
      expect(
        () => requirements.validate(AppSpec.parse(_packing186Json)),
        returnsNormally,
      );
      expect(
        () => requirements.validate(AppSpec.parse(_packing183Json)),
        mismatch,
      );
    },
  );

  test('that-is-optional checkbox suffix preserves the UI requirement', () {
    final requirements = GenerationRequirements.fromRequest(
      'Add a packed checkbox that is optional.',
    );
    expect(requirements.recordCheckboxes.single.label, 'packed');
    expect(
      requirements.recordCheckboxes.single.requireBinaryInitialization,
      isFalse,
    );
    expect(
      () => requirements.validate(AppSpec.parse(_packing186Json)),
      returnsNormally,
    );
    expect(
      () => requirements.validate(AppSpec.parse(_packing183Json)),
      mismatch,
    );
  });

  test('unqualified checkbox references inherit the explicit optional declaration in either order', () {
    for (final request in [
      'Add an optional packed checkbox. Show the packed checkbox on the list.',
      'Show the packed checkbox on the list. Add an optional packed checkbox.',
      'Add Packed (optional checkbox). Show the packed checkbox on the list.',
      'Show the packed checkbox on the list. Add Packed (optional checkbox).',
    ]) {
      final requirements = GenerationRequirements.fromRequest(request);
      expect(
        requirements.recordCheckboxes.single.label.toLowerCase(),
        'packed',
      );
      expect(
        requirements.recordCheckboxes.single.requireBinaryInitialization,
        isFalse,
      );
      expect(
        () => requirements.validate(AppSpec.parse(_packing186Json)),
        returnsNormally,
      );
      expect(
        () => requirements.validate(AppSpec.parse(_packing183Json)),
        mismatch,
      );
    }
  });

  test('explicit checkbox accepts actual boolean and reversible workflow checklist UI', () {
    final requirements = GenerationRequirements.fromRequest(packingRequest);
    for (final json in [booleanCheckbox(), workflowCheckbox()]) {
      expect(() => requirements.validate(_spec(json)), returnsNormally);
    }
    final wrongChecked = workflowCheckbox();
    wrongChecked['views'][0]['options']['checkedValue'] = 'Unpacked';
    wrongChecked['views'][0]['options']['uncheckedValue'] = 'Packed';
    expect(() => requirements.validate(_spec(wrongChecked)), mismatch);
    final hidden = workflowCheckbox();
    // Keep the authored list route as the main page, with a hidden checklist.
    hidden['navigation']['pages'][0]['viewIds'] = ['plainList'];
    final plain = jsonDecode(_packing183Json)['views'][0] as Map;
    plain['id'] = 'plainList';
    hidden['views'].add(plain);
    expect(() => requirements.validate(_spec(hidden)), mismatch);
    final formOnly = booleanCheckbox();
    formOnly['views'][0]['type'] = 'list';
    (formOnly['views'][0] as Map).remove('options');
    expect(() => requirements.validate(_spec(formOnly)), mismatch);
  });

  test(
    'checkbox field resolves uniquely while multiple views may share it',
    () {
      final requirements = GenerationRequirements.fromRequest(packingRequest);
      final fields = booleanCheckbox();
      fields['collections'][0]['fields'].add({
        'id': 'otherPacked',
        'label': 'Packed',
        'type': 'boolean',
        'required': false,
      });
      expect(() => requirements.validate(_spec(fields)), mismatch);
      final controls = workflowCheckbox();
      final duplicate = jsonDecode(jsonEncode(controls['views'][0])) as Map;
      duplicate['id'] = 'otherChecklist';
      controls['views'].add(duplicate);
      controls['navigation']['pages'][0]['viewIds'].add('otherChecklist');
      expect(() => requirements.validate(_spec(controls)), returnsNormally);
    },
  );

  test('checkbox extraction excludes negative quoted example and ambiguous requirements', () {
    for (final request in [
      'Do not add a packed checkbox.',
      'A packed checkbox is not required.',
      'Never add a packed checkbox.',
      'For example, add a packed checkbox.',
      'Maybe add a packed checkbox.',
      'Consider a packed checkbox later.',
      'The phrase "a packed checkbox" is documentation.',
      "The phrase 'a packed checkbox' is documentation.",
      'The phrase `a packed checkbox` is documentation.',
      'Add a packed checkbox or a status menu.',
      'Add a packed checkbox. Do not add a packed checkbox.',
      'Add Packed (required checkbox). Do not add Packed (required checkbox).',
      'Use one Books collection and one Packing collection with a packed checkbox.',
      'Build two apps with a packed checkbox.',
      'I want a list of packed items.',
      'Build a packing checklist.',
    ]) {
      expect(
        GenerationRequirements.fromRequest(request).recordCheckboxes,
        isEmpty,
        reason: request,
      );
    }
    final otherLabel = GenerationRequirements.fromRequest(
      'Add an archived checkbox.',
    );
    expect(otherLabel.recordCheckboxes.single.label, 'archived');
    expect(
      GenerationRequirements.fromRequest('Save Done (required checkbox).')
          .recordCheckboxes
          .single
          .label,
      'Done',
    );
    expect(
      GenerationRequirements.fromRequest(
        'Use one Items collection with Packed (required checkbox).',
      ).recordCheckboxes.single.label,
      'Packed',
    );
  });

  Map<String, dynamic> numericForm({
    String label = 'Rating',
    String type = 'integer',
    Map<String, dynamic>? control,
  }) {
    final json = _reading();
    json['collections'][0]['fields'].add({
      'id': 'authoredValue',
      'label': label,
      'type': type,
      'required': false,
    });
    json['views'][2]['fieldIds'].add('authoredValue');
    if (control != null) {
      json['requires'].add('views.interactive.v1');
      json['views'][2]['options'] = {
        'controls': [
          {'fieldId': 'authoredValue', ...control},
        ],
      };
    }
    return json;
  }

  test('literal rating ranges serialize as reachable input requirements', () {
    const request =
        'Make a personal reading journal. Save book title, author, '
        'reading status (To read, Reading, Finished), a rating from 1 to 5, and notes.';
    final requirements = GenerationRequirements.fromRequest(request);
    expect(requirements.isEmpty, isFalse);
    expect(requirements.toJson(), {
      'numericInputRanges': [
        {
          'label': 'rating',
          'type': 'integer',
          'min': 1,
          'max': 5,
          'reachableCreateAndEditForms': true,
        },
      ],
    });
    // Reproduce app174's semantic defect: a valid stored integer is exposed
    // through the default unbounded input, rather than a requested 1–5 control.
    expect(
      () => requirements.validate(_spec(numericForm())),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'range diagnostic',
          contains('bounded numeric control from 1 to 5'),
        ),
      ),
    );
    for (final control in [
      {'control': 'rating'},
      {'control': 'slider', 'min': 1, 'max': 5, 'step': 1},
      {'control': 'stepper', 'min': 1, 'max': 5, 'step': 1},
    ]) {
      final spec = _spec(numericForm(control: control));
      expect(() => requirements.validate(spec), returnsNormally);
      expect(
        spec.collection('books').behavior('readingProgress').type,
        'workflow.v1',
      );
    }
    final user = jsonDecode(
      buildAiRequest(
            'test',
            request,
            _spec(_reading()),
            editing: false,
          )['messages'].last['content']
          as String,
    ) as Map;
    expect(user['explicitRequirements'], requirements.toJson());
  });

  test(
    'literal numeric labels, types and ranges use exact authored bindings',
    () {
      for (final example in [
        (
          request: 'Save Score (required integer from 2 to 7).',
          label: 'Score',
          type: 'integer',
          min: 2,
          max: 7,
          step: 1,
        ),
        (
          request: 'Use one Measurements collection with Temperature (optional number from -2.5 to 8.5).',
          label: 'Temperature',
          type: 'number',
          min: -2.5,
          max: 8.5,
          step: 0.5,
        ),
        (
          request: 'Add a mood rating from 0 to 10.',
          label: 'Mood rating',
          type: 'integer',
          min: 0,
          max: 10,
          step: 1,
        ),
      ]) {
        final requirements = GenerationRequirements.fromRequest(
          example.request,
        );
        expect(
          requirements.numericInputRanges,
          hasLength(1),
          reason: example.request,
        );
        final json = numericForm(
          label: example.label,
          type: example.type,
          control: {
            'control': 'stepper',
            'min': example.min,
            'max': example.max,
            'step': example.step,
          },
        );
        expect(() => requirements.validate(_spec(json)), returnsNormally);
        json['views'][2]['options']['controls'][0]['max'] = example.max + 1;
        expect(() => requirements.validate(_spec(json)), mismatch);
      }
      final wrongType = numericForm(
        label: 'Rating',
        type: 'number',
        control: {
          'control': 'slider',
          'min': 1,
          'max': 5,
          'step': 1,
        },
      );
      expect(
        () =>
            GenerationRequirements.fromRequest('Add a rating from 1 to 5.')
                .validate(_spec(wrongType)),
        mismatch,
      );
      final missingLabel = numericForm(
        label: 'Other',
        control: {'control': 'rating'},
      );
      expect(
        () =>
            GenerationRequirements.fromRequest('Add a rating from 1 to 5.')
                .validate(_spec(missingLabel)),
        mismatch,
      );
    },
  );

  test(
    'numeric requirements ignore negatives, quotes and ambiguous ranges',
    () {
      for (final request in [
        'Do not add a rating from 1 to 5.',
        "I don't need a rating from 1 to 5.",
        'A rating from 1 to 5 is not needed.',
        'For example, add a rating from 1 to 5.',
        'Maybe add a rating from 1 to 5.',
        'The phrase "a rating from 1 to 5" is documentation.',
        "The phrase 'a rating from 1 to 5' is documentation.",
        'The phrase `a rating from 1 to 5` is documentation.',
        'The phrase “a rating from 1 to 5” is documentation.',
        'Add a rating from 1 to 5 or 0 to 10.',
        'Save Score (optional integer from 2 to 7) or omit it.',
        'Add a rating from 1 to 5. Add a rating from 0 to 10.',
        'Use one Books collection and one Films collection with a rating from 1 to 5.',
        'Add a rating from 5 to 1.',
        'Add a rating from 1.5 to 5.',
        'Save Score (optional integer from 0 to 10000000000000000).',
        'I finished five books and gave one a rating.',
        'Add a numeric rating.',
      ]) {
        expect(
          GenerationRequirements.fromRequest(request).numericInputRanges,
          isEmpty,
          reason: request,
        );
      }
    },
  );

  test('hidden bounded forms and alternative unbounded routes cannot satisfy a range', () {
    final requirements = GenerationRequirements.fromRequest(
      'Add a rating from 1 to 5.',
    );
    final json = numericForm(control: {'control': 'rating'});
    final other = jsonDecode(jsonEncode(json['views'][2])) as Map;
    other['id'] = 'unboundedForm';
    other.remove('options');
    json['views'].add(other);
    json['navigation']['pages'].add({
      'id': 'unboundedPage',
      'title': 'Other editor',
      'viewIds': ['unboundedForm'],
    });
    // Hidden extra forms do not matter until a live record route exposes one.
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    json['views'][1]['formPageId'] = 'unboundedPage';
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['views'][0]['formPageId'] = 'unboundedPage';
    expect(() => requirements.validate(_spec(json)), mismatch);
  });

  test('record grammar guards require literal affirmative single-collection routes', () {
    const one = 'Use one Tasks collection with Title (required text). ';
    const routes =
        'Include dedicated Task details and shared Add/Edit task pages.';
    final exact = GenerationRequirements.fromRequest('$one$routes');
    expect(exact.singleRecordCollection, isTrue);
    expect(exact.dedicatedRecordRoutes, isTrue);
    expect(
      GenerationRequirements.fromRequest('$one Do not $routes')
          .dedicatedRecordRoutes,
      isFalse,
    );
    for (final request in [
      'A useful records app. $routes',
      'Do not $one$routes',
      '${one}Use one People collection with Name (required text). $routes',
      '${one}Add another People collection. $routes',
      '${one}Also add a People collection with Name (required text). $routes',
    ]) {
      final ambiguous = GenerationRequirements.fromRequest(request);
      expect(ambiguous.singleRecordCollection, isFalse, reason: request);
      expect(ambiguous.dedicatedRecordRoutes, isFalse, reason: request);
    }
    expect(
      GenerationRequirements.fromRequest(
        'Use a single Ledger collection with Entry (required text). '
        'Include dedicated Entry details and a shared Add/Edit entry page.',
      ).dedicatedRecordRoutes,
      isTrue,
    );
  });

  test('literal participant creation requires a shared member-write policy without assigning identities', () {
    for (final request in [
      _potluckRequest,
      'Build a reading log where friends can create their reviews.',
      'Let members add their own records to the tracker.',
      'Everyone adds their recipe.',
      'Participants should submit their suggestions.',
    ]) {
      final requirements = GenerationRequirements.fromRequest(request);
      expect(requirements.sharedRecordCreation, isTrue, reason: request);
      expect(requirements.policy, isNull);
      expect(requirements.preferredPolicy, 'groupWorkflow.v1');
      expect(requirements.toJson(), {
        'policyPresetRequest': 'groupWorkflow.v1',
        'sharedRecordCreation': true,
      });
      expect(() => requirements.validate(_spec(_reading())), mismatch);
      final shared = _reading()..['policyPresetRequest'] = 'groupWorkflow.v1';
      expect(() => requirements.validate(_spec(shared)), returnsNormally);
      // No workflow behavior, capacity pool or membership grant is inferred
      // from the access request; a shared journal can use ordinary CRUD.
      shared['collections'][0]['behaviors'] = [];
      shared['collections'][0]['fields'][1]['required'] = false;
      shared['actions'].removeLast();
      for (final view in shared['views'] as List) {
        (view['actionIds'] as List).remove('changeReadingStatus');
      }
      expect(() => requirements.validate(_spec(shared)), returnsNormally);
    }
  });

  test('schema-valid personal potluck159 is rejected for the exact shared creation request', () {
    // Cohort5 app159 declared personalTracker despite the explicit everyone
    // add-their-dish request. This reproduces its access defect independently
    // of unrelated fields, pages and progress presentation.
    final personal = _spec(_reading());
    expect(personal.policyPresetRequest, 'personalTracker.v1');
    expect(
      () =>
          GenerationRequirements.fromRequest(_potluckRequest)
              .validate(personal),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'shared member writes',
          contains(
            'participant record creation needs policyPresetRequest groupWorkflow.v1',
          ),
        ),
      ),
    );
  });

  test('shared creation skips negatives, examples, viewing-only friends and ambiguous scopes', () {
    for (final request in [
      'Do not let everyone add their dish.',
      'Never let members create their records.',
      'For example, friends can create their reviews.',
      'Maybe everyone can add their dish.',
      'Everyone can add their dish only as an example.',
      'I track the recipes my friends give me.',
      'My friends can view my records.',
      'Build a shared neighborhood cookbook.',
      'Everyone can add their dish. Build another private notes app.',
      'Build a potluck app where everyone can add their dish and a separate notes app.',
      'Let members add their records across two collections.',
    ]) {
      final requirements = GenerationRequirements.fromRequest(request);
      expect(requirements.sharedRecordCreation, isFalse, reason: request);
      expect(requirements.preferredPolicy, isNull, reason: request);
    }
  });

  test('explicit policies retain precedence and shared contracts are creation-only in provider requests', () {
    for (final policy in policyPresets) {
      final request = 'Use $policy. Let members add their records.';
      final requirements = GenerationRequirements.fromRequest(request);
      expect(requirements.sharedRecordCreation, isFalse);
      expect(requirements.policy, policy);
      expect(requirements.preferredPolicy, policy);
      expect(requirements.toJson(), {'policyPresetRequest': policy});
    }
    for (final request in [
      'Use personalTracker.v1 or use groupWorkflow.v1. Let everyone add their dish.',
      'Use personalTracker.v1 or groupWorkflow.v1. Let everyone add their dish.',
      'Use groupWorkflow.v1 versus groupCapacitySignup.v1. Let members add their records.',
    ]) {
      final ambiguous = GenerationRequirements.fromRequest(request);
      expect(ambiguous.sharedRecordCreation, isFalse, reason: request);
      expect(ambiguous.preferredPolicy, isNull, reason: request);
    }
    final single = GenerationRequirements.fromRequest(
      'Use groupWorkflow.v1. Do not use personalTracker.v1. Let members add their records.',
    );
    expect(single.preferredPolicy, 'groupWorkflow.v1');
    final creation = buildAiRequest(
      'test',
      _potluckRequest,
      _spec(_reading()),
      editing: false,
    );
    final user =
        jsonDecode(creation['messages'].last['content'] as String) as Map;
    expect(user['explicitRequirements'], {
      'policyPresetRequest': 'groupWorkflow.v1',
      'sharedRecordCreation': true,
    });
    final edit = buildAiRequest(
      'test',
      _potluckRequest,
      _spec(_reading()),
      editing: true,
    );
    expect(
      jsonDecode(edit['messages'].last['content'] as String),
      isNot(contains('explicitRequirements')),
    );
  });

  test('explicit personal inbox scheduling serializes requirements without authored identities', () {
    final requirements = GenerationRequirements.fromRequest(_inboxRequest);
    expect(requirements.isEmpty, isFalse);
    expect(requirements.toJson(), {
      'ownerInboxReminder': {
        'effect': 'notifyOwner',
        'optionalTimestamp': true,
        'distinctOptionalDueDate': true,
        'openCompletedCondition': true,
      },
    });
    expect(
      () => requirements.validate(_spec(_ownerReminders())),
      returnsNormally,
    );
    final simple = GenerationRequirements.fromRequest(
      'Add reminders for my AppNest inbox.',
    ).ownerInboxReminder!;
    expect(simple.optionalTimestamp, isFalse);
    expect(simple.distinctOptionalDueDate, isFalse);
    expect(simple.openCompletedCondition, isFalse);
  });

  test('negative examples and ambiguous reminder scopes remain provider interpretation', () {
    for (final request in [
      'Do not $_inboxRequest',
      'Never $_inboxRequest',
      'For example, $_inboxRequest',
      'A sample request: $_inboxRequest',
      'Maybe $_inboxRequest',
      '$_inboxRequest Build another recipes app.',
      '$_inboxRequest Add two household collections.',
      'Build shared team reminders for my AppNest inbox.',
      'Add reminders for my AppNest inbox and owner inbox.',
      'Build a personal reminder app with an email inbox.',
      'Build an inbox record view with reminder times.',
      'Add reminders to my AppNest inbox only as an example.',
    ]) {
      expect(
        GenerationRequirements.fromRequest(request).ownerInboxReminder,
        isNull,
        reason: request,
      );
    }
    final optionalNegative = GenerationRequirements.fromRequest(
      'Add reminders for my AppNest inbox. Do not add optional due dates. '
      'No separate optional reminder time. No open and completed states.',
    ).ownerInboxReminder!;
    expect(optionalNegative.optionalTimestamp, isFalse);
    expect(optionalNegative.distinctOptionalDueDate, isFalse);
    expect(optionalNegative.openCompletedCondition, isFalse);
  });

  test('schema-valid reminder158 omission cannot satisfy the explicit inbox request', () {
    // Cohort4 app158 reached preview with personal policy, Open/Completed,
    // optional due/reminder timestamps, and automationRequests: []. The
    // scheduling omission is independent of the candidate's display widgets.
    final json = _ownerReminders()..['automationRequests'] = <dynamic>[];
    final spec = _spec(json);
    expect(spec.policyPresetRequest, 'personalTracker.v1');
    expect(spec.automationRequests, isEmpty);
    expect(
      () => GenerationRequirements.fromRequest(_inboxRequest).validate(spec),
      throwsA(
        isA<SpecException>().having(
          (error) => error.message,
          'missing delivery rule',
          contains('notifyOwner inApp effect'),
        ),
      ),
    );
    expect(
      () => const GenerationRequirements().validate(spec),
      returnsNormally,
    );
  });

  test('owner inbox gate requires optional separate dates and the declared Open condition', () {
    final requirements = GenerationRequirements.fromRequest(_inboxRequest);
    final requiredTime = _ownerReminders();
    requiredTime['collections'][0]['fields'][3]['required'] = true;
    expect(() => requirements.validate(_spec(requiredTime)), mismatch);
    final requiredDue = _ownerReminders();
    requiredDue['collections'][0]['fields'][2]['required'] = true;
    expect(() => requirements.validate(_spec(requiredDue)), mismatch);
    final noCondition = _ownerReminders();
    (noCondition['automationRequests'][0] as Map).remove('condition');
    expect(() => requirements.validate(_spec(noCondition)), mismatch);
    final completedCondition = _ownerReminders();
    completedCondition['automationRequests'][0]['condition']['value'] =
        'Completed';
    expect(() => requirements.validate(_spec(completedCondition)), mismatch);
    final otherVocabulary = _ownerReminders();
    otherVocabulary['collections'][0]['fields'][1]['choices'] = [
      'Open',
      'Done',
    ];
    otherVocabulary['collections'][0]['behaviors'][0]['transitions'] = {
      'Open': ['Done'],
      'Done': ['Open'],
    };
    expect(() => requirements.validate(_spec(otherVocabulary)), mismatch);
    final casing = _ownerReminders();
    casing['collections'][0]['fields'][1]['choices'] = ['open', 'completed'];
    casing['collections'][0]['behaviors'][0]['transitions'] = {
      'open': ['completed'],
      'completed': ['open'],
    };
    casing['automationRequests'][0]['condition']['value'] = 'open';
    expect(() => requirements.validate(_spec(casing)), returnsNormally);
  });

  test('an explicit separate reminder time cannot reuse the optional due-date calendar field', () {
    final json = _ownerReminders();
    json['requires'].add('views.calendar.v1');
    json['views'].add({
      'id': 'dueDates',
      'type': 'calendar',
      'collectionId': 'books',
      'titleFieldId': 'title',
      'options': {'dateFieldId': 'targetMoment'},
      'actionIds': <dynamic>[],
    });
    json['navigation']['pages'].add({
      'id': 'dueDatesPage',
      'title': 'Due dates',
      'viewIds': ['dueDates'],
    });
    json['navigation']['tabs'].add({
      'pageId': 'dueDatesPage',
      'label': 'Due dates',
      'icon': 'today',
    });
    final requirements = GenerationRequirements.fromRequest(_inboxRequest);
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    json['automationRequests'][0]['trigger']['fieldId'] = 'targetMoment';
    expect(() => requirements.validate(_spec(json)), mismatch);
  });

  test('literal standalone search supports visible text lists and tables without choice filters', () {
    final requirements = GenerationRequirements.fromRequest(
      'I want a searchable list without choice filters.',
    );
    expect(requirements.searchableList, isTrue);
    expect(requirements.filters, isEmpty);
    final json = _reading();
    expect(json['views'][0]['filterFieldIds'], isNull);
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    json['views'][0].remove('titleFieldId');
    expect(() => requirements.validate(_spec(json)), mismatch);
    // Text on the dedicated hidden details view does not expose Search.
    json['views'][1]['titleFieldId'] = 'title';
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['views'][0]['type'] = 'table';
    json['views'][0]['titleFieldId'] = 'title';
    json['requires'].add('views.table.v1');
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    final tableRequest = GenerationRequirements.fromRequest(
      'Add a searchable table.',
    );
    expect(tableRequest.searchableList, isTrue);
    expect(() => tableRequest.validate(_spec(json)), returnsNormally);
    for (final request in [
      'Do not add a searchable list.',
      'For example, add a searchable list.',
      'Maybe add a searchable table.',
      'A searchable list is not needed.',
      'Let me find books by name.',
    ]) {
      expect(
        GenerationRequirements.fromRequest(request).searchableList,
        isFalse,
        reason: request,
      );
    }
  });

  test('provider gets explicit inbox requirements for creation while edits retain their existing contract', () {
    final creation = buildAiRequest(
      'test',
      _inboxRequest,
      _spec(_reading()),
      editing: false,
    );
    final user =
        jsonDecode(creation['messages'].last['content'] as String) as Map;
    expect(
      user['explicitRequirements'],
      GenerationRequirements.fromRequest(_inboxRequest).toJson(),
    );
    expect(user.containsKey('currentDefinition'), isFalse);
    final edit = buildAiRequest(
      'test',
      _inboxRequest,
      _spec(_reading()),
      editing: true,
    );
    final edited =
        jsonDecode(edit['messages'].last['content'] as String) as Map;
    expect(edited, isNot(contains('explicitRequirements')));
  });

  test('explicit policies are enforced without inferring ambiguous prose', () {
    final requirements = GenerationRequirements.fromRequest(
      'Use groupWorkflow.v1 for our shared reading journal.',
    );
    expect(() => requirements.validate(_spec(_reading())), mismatch);
    final shared = _reading()..['policyPresetRequest'] = 'groupWorkflow.v1';
    expect(() => requirements.validate(_spec(shared)), returnsNormally);
    expect(
      GenerationRequirements.fromRequest(
        'Build a packing app with the personalTracker.v1 policy.',
      ).policy,
      'personalTracker.v1',
    );
    for (final request in [
      'A household app',
      'Do not use personalTracker.v1.',
      'Never use personalTracker.v1.',
      'Do not build an app using personalTracker.v1.',
      'Use personalTracker.v1 or use groupWorkflow.v1; I have not decided.',
    ]) {
      expect(GenerationRequirements.fromRequest(request).policy, isNull);
    }
  });

  test('exact choice vocabulary and initial ordering survive defaults', () {
    final requirements = GenerationRequirements.fromRequest(
      'Use one Packing items collection with Item (required text), '
      'Category (required choice: Documents, Clothes, Other), Quantity (required integer), '
      'and Packing status (required choice: To pack, Packed).',
    );
    expect(requirements.choices, {
      'Category': ['Documents', 'Clothes', 'Other'],
      'Packing status': ['To pack', 'Packed'],
    });
    final json = _reading();
    json['collections'][0]['fields'][1]['label'] = 'Packing status';
    json['collections'][0]['fields'].add({
      'id': 'category',
      'label': 'Category',
      'type': 'choice',
      'required': false,
      'choices': ['Documents', 'Clothes', 'Other'],
    });
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['collections'][0]['fields'][1]['choices'] = ['To pack', 'Packed'];
    json['collections'][0]['behaviors'][0]['transitions'] = {
      'To pack': ['Packed'],
      'Packed': ['To pack'],
    };
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    json['collections'][0]['fields'][1]['choices'] = ['Packed', 'To pack'];
    expect(() => requirements.validate(_spec(json)), mismatch);
  });

  test(
    'choice filters must be on a visible record view, not display fields',
    () {
      final requirements = GenerationRequirements.fromRequest(
        'Use fields Title (required text), and Status (required choice: To read, Read). '
        'Make a searchable list and Status filter.',
      );
      expect(requirements.filters, ['Status']);
      final json = _reading();
      expect(() => requirements.validate(_spec(json)), mismatch);
      json['views'][0]['filterFieldIds'] = ['status'];
      expect(() => requirements.validate(_spec(json)), returnsNormally);
      json['views'][0].remove('filterFieldIds');
      json['views'][1]['filterFieldIds'] = ['status'];
      expect(() => requirements.validate(_spec(json)), mismatch);
    },
  );

  test('slash-separated filters preserve each named field', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Category (required choice: Work, Home), and Packing status (required choice: To pack, Packed). '
      'Use a searchable list and Category/Packing status filters.',
    );
    expect(requirements.filters, ['Category', 'Packing status']);
  });

  test('negative filter and summary examples do not become requirements', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), and Status (required choice: To read, Read). '
      'Do not add Status filters. No grouped counts by Status.',
    );
    expect(requirements.choices.keys, ['Status']);
    expect(requirements.filters, isEmpty);
    expect(requirements.groupedSummaries, isEmpty);
  });

  test('negative field and filtered-tab examples are not inferred', () {
    expect(
      GenerationRequirements.fromRequest(
        'Do not add Status (required choice: Open, Done).',
      ).choices,
      isEmpty,
    );
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Do not add a Finished tab filtered to Read.',
    );
    expect(requirements.filteredTabs, isEmpty);
  });

  test('a requested searchable filtered list needs a text title binding', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add a searchable saved-item list with Status filters.',
    );
    expect(requirements.searchableList, isTrue);
    final json = _reading();
    json['views'][0]['filterFieldIds'] = ['status'];
    json['views'][0].remove('titleFieldId');
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['views'][0]['titleFieldId'] = 'title';
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    final negative = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add Status filters. Do not add a searchable list.',
    );
    expect(negative.searchableList, isFalse);
  });

  test('a total cannot satisfy a requested grouped summary', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add a Progress tab with grouped counts by Status.',
    );
    expect(requirements.groupedSummaries, ['Status']);
    final json = _reading();
    json['requires'].add('views.summary.v1');
    json['views'].add({
      'id': 'progress',
      'type': 'summary',
      'collectionId': 'books',
    });
    json['navigation']['pages'].add({
      'id': 'progressPage',
      'title': 'Progress',
      'viewIds': ['progress'],
    });
    json['navigation']['tabs'].add({
      'pageId': 'progressPage',
      'label': 'Progress',
      'icon': 'chart',
    });
    expect(() => requirements.validate(_spec(json)), mismatch);
    json['views'].last['groupByFieldId'] = 'status';
    expect(() => requirements.validate(_spec(json)), returnsNormally);
  });

  test('a filtered tab must constrain every record view on that tab', () {
    final requirements = GenerationRequirements.fromRequest(
      'Fields Title (required text), Status (required choice: To read, Read). '
      'Add a Finished tab filtered to Read and an Overview tab.',
    );
    expect(requirements.filteredTabs, {'Finished': 'Read'});
    final json = _reading();
    final list = Map<String, dynamic>.from(json['views'][0] as Map)
      ..['id'] = 'finishedList';
    json['views'].add(list);
    json['navigation']['pages'].add({
      'id': 'finishedPage',
      'title': 'Finished',
      'viewIds': ['finishedList'],
    });
    json['navigation']['tabs'].add({
      'pageId': 'finishedPage',
      'label': 'Finished',
      'icon': 'list',
    });
    expect(() => requirements.validate(_spec(json)), mismatch);
    list['query'] = {
      'filters': [
        {'fieldId': 'status', 'operator': 'eq', 'value': 'Read'},
      ],
    };
    expect(() => requirements.validate(_spec(json)), returnsNormally);
    final second = Map<String, dynamic>.from(json['views'][0] as Map)
      ..['id'] = 'unfilteredList';
    json['views'].add(second);
    json['navigation']['pages'].last['viewIds'].add('unfilteredList');
    expect(() => requirements.validate(_spec(json)), mismatch);
  });

  test('shared log grouping request remains separate from task workflow', () {
    final requirements = GenerationRequirements.fromRequest(
      'Use groupWorkflow.v1. Fields Pet (required text), Activity (required choice: Feeding, Walk). '
      'A searchable list and Activity filter, and a Summary tab grouping saved entries by Activity. '
      'Do not add a task-status workflow.',
    );
    expect(requirements.policy, 'groupWorkflow.v1');
    expect(requirements.filters, ['Activity']);
    expect(requirements.groupedSummaries, ['Activity']);
  });

  test('provider receives literal creation requirements without draft content', () {
    const request =
        'Use groupWorkflow.v1. Fields Status (required choice: Started, Finished).';
    final body = buildAiRequest(
      'test',
      request,
      _spec(_reading()),
      editing: false,
    );
    final user = jsonDecode(body['messages'].last['content'] as String) as Map;
    expect(user['explicitRequirements'], {
      'policyPresetRequest': 'groupWorkflow.v1',
      'exactChoiceFields': {
        'Status': ['Started', 'Finished'],
      },
    });
    expect(user.containsKey('currentDefinition'), isFalse);
    final edit = buildAiRequest(
      'test',
      request,
      _spec(_reading()),
      editing: true,
    );
    expect(
      jsonDecode(edit['messages'].last['content'] as String),
      isNot(contains('explicitRequirements')),
    );
  });
}
