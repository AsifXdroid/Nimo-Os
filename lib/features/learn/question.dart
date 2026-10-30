/// LEARN engine — question payload validation (§R4.1/§R4.4/§R4B).
/// PURE: takes the already-decoded JSON value, returns a list of
/// human-readable issues (empty = valid). The store refuses to
/// write a payload with issues, and the S5 pack importer (step B)
/// reports them verbatim against the offending pack question.
///
/// Payloads are JSON objects whose shape depends on `type`.
/// Unknown extra fields are tolerated (forward compatibility),
/// except where a rule below constrains an optional field's type.
library;

/// Every question type the engine knows how to ask (§R4B).
const List<String> questionTypes = [
  'mcq',
  'flashcard',
  'cloze',
  'image_point',
  'ordering',
  'scenario',
  'mythfact',
];

bool isKnownType(String type) => questionTypes.contains(type);

/// Difficulty must be an int in 1–5 when present. `null` (absent)
/// is valid — callers apply the default of 3.
List<String> validateDifficulty(Object? difficulty) {
  if (difficulty == null) return const [];
  if (difficulty is! int) {
    return ['difficulty must be an integer 1–5'];
  }
  if (difficulty < 1 || difficulty > 5) {
    return ['difficulty must be between 1 and 5'];
  }
  return const [];
}

/// Validate [decodedJson] as the payload for a question of
/// [type]. Returns human-readable issues; empty means valid.
List<String> validatePayload(String type, Object? decodedJson) {
  if (!isKnownType(type)) {
    return ['unknown question type: $type'];
  }
  if (decodedJson is! Map) {
    return ['payload must be a JSON object'];
  }
  final p = decodedJson.cast<String, Object?>();
  final issues = <String>[
    ...switch (type) {
      'mcq' => _validateMcq(p),
      'flashcard' => _validateFlashcard(p),
      'cloze' => _validateCloze(p),
      'image_point' => _validateImagePoint(p),
      'ordering' => _validateOrdering(p),
      'scenario' => _validateScenario(p),
      'mythfact' => _validateMythFact(p),
      _ => const <String>[],
    },
  ];
  // A payload may carry its own difficulty; when it does it must
  // obey the same 1–5 rule as the column value.
  if (p.containsKey('difficulty')) {
    issues.addAll(validateDifficulty(p['difficulty']));
  }
  return issues;
}

// ------------------------------------------------------------ helpers

bool _isNonEmptyString(Object? v) => v is String && v.trim().isNotEmpty;

Map<String, Object?>? _asMap(Object? v) =>
    v is Map ? v.cast<String, Object?>() : null;

bool _isNumIn(Object? v, num min, num max) => v is num && v >= min && v <= max;

void _checkOptionalString(
  Map<String, Object?> p,
  String key,
  List<String> issues,
) {
  final v = p[key];
  if (v != null && v is! String) issues.add('$key must be a string');
}

List<String> _idIssues(Object? id, String what) {
  // Choice/item ids are non-empty strings in every pack the
  // research specifies; numbers are also accepted so hand-made
  // packs with numeric ids are not rejected spuriously.
  if (id is String && id.trim().isNotEmpty) return const [];
  if (id is num) return const [];
  return ['$what id must be a non-empty string'];
}

// ------------------------------------------------------------ mcq

List<String> _validateMcq(Map<String, Object?> p) {
  final issues = <String>[];
  if (!_isNonEmptyString(p['prompt'])) {
    issues.add('mcq prompt must be a non-empty string');
  }
  final choiceIds = <Object?>[];
  final rawChoices = p['choices'];
  if (rawChoices is! List) {
    issues.add('mcq choices must be a list of 2–5 choices');
  } else {
    if (rawChoices.length < 2 || rawChoices.length > 5) {
      issues.add('mcq choices must contain 2–5 items');
    }
    for (final raw in rawChoices) {
      final c = _asMap(raw);
      if (c == null) {
        issues.add('each mcq choice must be an object {id, text}');
        continue;
      }
      issues.addAll(_idIssues(c['id'], 'mcq choice'));
      if (c['id'] != null) {
        if (choiceIds.contains(c['id'])) {
          issues.add('mcq choice ids must be unique');
        }
        choiceIds.add(c['id']);
      }
      if (!_isNonEmptyString(c['text'])) {
        issues.add('each mcq choice text must be a non-empty string');
      }
    }
  }
  final correct = p['correctChoiceIds'];
  if (correct is! List) {
    issues.add('mcq correctChoiceIds must be a list with exactly 1 id');
  } else {
    if (correct.length != 1) {
      issues.add('mcq correctChoiceIds must contain exactly 1 id');
    }
    for (final id in correct) {
      if (!choiceIds.contains(id)) {
        issues.add('mcq correctChoiceIds must name an existing choice');
      }
    }
  }
  final shuffle = p['shuffle'];
  if (shuffle != null && shuffle is! bool) {
    issues.add('mcq shuffle must be a bool');
  }
  _checkOptionalString(p, 'explanation', issues);
  _checkOptionalString(p, 'hint', issues);
  return issues;
}

// ------------------------------------------------------------ flashcard

List<String> _validateFlashcard(Map<String, Object?> p) {
  final issues = <String>[];
  if (!_isNonEmptyString(p['front'])) {
    issues.add('flashcard front must be a non-empty string');
  }
  if (!_isNonEmptyString(p['back'])) {
    issues.add('flashcard back must be a non-empty string');
  }
  return issues;
}

// ------------------------------------------------------------ cloze

List<String> _validateCloze(Map<String, Object?> p) {
  final issues = <String>[];
  final text = p['text'];
  if (!_isNonEmptyString(text)) {
    issues.add('cloze text must be a non-empty string');
    return issues;
  }
  final s = text as String;
  var spans = 0;
  var i = 0;
  var balanced = true;
  while (i < s.length) {
    final open = s.indexOf('{{', i);
    final strayClose = s.indexOf('}}', i);
    if (strayClose >= 0 && (open < 0 || strayClose < open)) {
      balanced = false; // a '}}' with no opening before it
      break;
    }
    if (open < 0) break;
    final close = s.indexOf('}}', open + 2);
    if (close < 0) {
      balanced = false; // unclosed span
      break;
    }
    final answer = s.substring(open + 2, close);
    if (answer.contains('{{')) balanced = false; // nested opening
    if (answer.trim().isEmpty) {
      issues.add('each cloze {{answer}} span must be non-empty');
    }
    spans++;
    i = close + 2;
  }
  if (!balanced) issues.add('cloze {{answer}} spans must be balanced');
  if (spans == 0 && balanced) {
    issues.add('cloze text must contain at least one {{answer}} span');
  }
  return issues;
}

// ------------------------------------------------------------ image_point

List<String> _validateImagePoint(Map<String, Object?> p) {
  final issues = <String>[];
  if (!_isNonEmptyString(p['prompt'])) {
    issues.add('image_point prompt must be a non-empty string');
  }
  if (!_isNonEmptyString(p['image'])) {
    issues.add('image_point image must be a non-empty string (media id)');
  }
  final target = _asMap(p['target']);
  if (target == null) {
    issues.add('image_point target must be an object {cx, cy, r}');
  } else {
    if (!_isNumIn(target['cx'], 0, 1)) {
      issues.add('image_point target cx must be a number in [0, 1]');
    }
    if (!_isNumIn(target['cy'], 0, 1)) {
      issues.add('image_point target cy must be a number in [0, 1]');
    }
    if (!_isNumIn(target['r'], 0.03, 0.25)) {
      issues.add('image_point target r must be a number in [0.03, 0.25]');
    }
  }
  final acceptable = p['acceptablePoints'];
  if (acceptable != null) {
    if (acceptable is! List) {
      issues.add('image_point acceptablePoints must be a list');
    } else {
      for (final raw in acceptable) {
        final pt = _asMap(raw);
        if (pt == null ||
            !_isNumIn(pt['cx'], 0, 1) ||
            !_isNumIn(pt['cy'], 0, 1)) {
          issues.add(
            'each image_point acceptablePoint must have cx, cy in [0, 1]',
          );
        }
      }
    }
  }
  return issues;
}

// ------------------------------------------------------------ ordering

List<String> _validateOrdering(Map<String, Object?> p) {
  final issues = <String>[];
  if (!_isNonEmptyString(p['prompt'])) {
    issues.add('ordering prompt must be a non-empty string');
  }
  final ids = <Object?>[];
  final rawItems = p['items'];
  if (rawItems is! List) {
    issues.add('ordering items must be a list of 2–8 items');
  } else {
    if (rawItems.length < 2 || rawItems.length > 8) {
      issues.add('ordering items must contain 2–8 items');
    }
    for (final raw in rawItems) {
      final item = _asMap(raw);
      if (item == null) {
        issues.add('each ordering item must be an object {id, text}');
        continue;
      }
      issues.addAll(_idIssues(item['id'], 'ordering item'));
      if (item['id'] != null) {
        if (ids.contains(item['id'])) {
          issues.add('ordering item ids must be unique');
        }
        ids.add(item['id']);
      }
      if (!_isNonEmptyString(item['text'])) {
        issues.add('each ordering item text must be a non-empty string');
      }
    }
  }
  final order = p['correctOrder'];
  if (order is! List) {
    issues.add('ordering correctOrder must be a permutation of the item ids');
  } else if (ids.isNotEmpty) {
    final isPermutation =
        order.length == ids.length &&
        order.every(ids.contains) &&
        order.toSet().length == order.length;
    if (!isPermutation) {
      issues.add('ordering correctOrder must be a permutation of the item ids');
    }
  }
  return issues;
}

// ------------------------------------------------------------ scenario

List<String> _validateScenario(Map<String, Object?> p) {
  final issues = <String>[];
  final nodesRaw = p['nodes'];
  final nodes = _asMap(nodesRaw);
  if (nodes == null) {
    issues.add('scenario nodes must be an object of 2–5 nodes');
    return issues;
  }
  if (nodes.length < 2 || nodes.length > 5) {
    issues.add('scenario must have 2–5 nodes (capped branching)');
    // Stop here: a hostile payload can declare a huge node map,
    // and every walk below (per-node checks, both BFS passes) is
    // wasted work once the count alone already condemns it.
    return issues;
  }
  final start = p['startNode'];
  if (start is! String || !nodes.containsKey(start)) {
    issues.add('scenario startNode must name an existing node');
  }

  final edges = <String, List<String>>{};
  final endNodes = <String>{};
  for (final entry in nodes.entries) {
    final nodeId = entry.key;
    final node = _asMap(entry.value);
    edges[nodeId] = [];
    if (node == null) {
      issues.add('scenario node "$nodeId" must be an object');
      continue;
    }
    if (!_isNonEmptyString(node['text'])) {
      issues.add('scenario node "$nodeId" text must be non-empty');
    }
    final isEnd = node['end'] == true;
    if (node.containsKey('end') && node['end'] is! bool) {
      issues.add('scenario node "$nodeId" end must be a bool');
    }
    final rawChoices = node['choices'];
    if (isEnd) {
      endNodes.add(nodeId);
      if (!_isNonEmptyString(node['summary'])) {
        issues.add('scenario end node "$nodeId" must have a non-empty summary');
      }
      if (rawChoices is List && rawChoices.isNotEmpty) {
        issues.add('scenario end node "$nodeId" must have no choices');
      } else if (rawChoices != null && rawChoices is! List) {
        issues.add('scenario end node "$nodeId" must have no choices');
      }
      continue;
    }
    if (rawChoices is! List || rawChoices.isEmpty || rawChoices.length > 3) {
      issues.add(
        'scenario node "$nodeId" must have 1–3 choices (or be an end node)',
      );
      if (rawChoices is! List) continue;
    }
    for (final raw in rawChoices) {
      final choice = _asMap(raw);
      if (choice == null) {
        issues.add('each scenario choice must be an object {text, next}');
        continue;
      }
      if (!_isNonEmptyString(choice['text'])) {
        issues.add('each scenario choice text must be non-empty');
      }
      final next = choice['next'];
      if (next is! String || !nodes.containsKey(next)) {
        issues.add('each scenario choice next must name an existing node');
      } else {
        edges[nodeId]!.add(next);
      }
      _checkOptionalString(choice, 'feedback', issues);
      if (choice['score'] != null && choice['score'] is! num) {
        issues.add('scenario choice score must be a number');
      }
    }
  }
  if (endNodes.isEmpty) {
    issues.add('scenario must have at least one end node');
  }

  // Graph integrity: BFS reachability from the start node, and
  // (via the reversed graph) every node must be able to reach an
  // end node — a cycle with no exit is an endless scenario.
  if (start is String && nodes.containsKey(start)) {
    final reachable = <String>{start};
    final queue = [start];
    var head = 0; // index pointer — removeAt(0) is O(n) per pop
    while (head < queue.length) {
      final cur = queue[head++];
      for (final next in edges[cur] ?? const <String>[]) {
        if (reachable.add(next)) queue.add(next);
      }
    }
    for (final id in nodes.keys) {
      if (!reachable.contains(id)) {
        issues.add('scenario node "$id" is not reachable from startNode');
      }
    }
    if (endNodes.isNotEmpty) {
      final reversed = <String, List<String>>{};
      edges.forEach((from, tos) {
        for (final to in tos) {
          (reversed[to] ??= []).add(from);
        }
      });
      final canReachEnd = {...endNodes};
      final q = [...endNodes];
      var qHead = 0; // index pointer, as in the forward BFS above
      while (qHead < q.length) {
        final cur = q[qHead++];
        for (final prev in reversed[cur] ?? const <String>[]) {
          if (canReachEnd.add(prev)) q.add(prev);
        }
      }
      for (final id in nodes.keys) {
        if (!canReachEnd.contains(id)) {
          issues.add('scenario node "$id" cannot reach an end node');
        }
      }
    }
  }
  return issues;
}

// ------------------------------------------------------------ mythfact

List<String> _validateMythFact(Map<String, Object?> p) {
  final issues = <String>[];
  if (!_isNonEmptyString(p['statement'])) {
    issues.add('mythfact statement must be a non-empty string');
  }
  if (p['isFact'] is! bool) {
    issues.add('mythfact isFact must be a bool');
  }
  if (!_isNonEmptyString(p['explanation'])) {
    issues.add('mythfact explanation must be a non-empty string');
  }
  return issues;
}
