import 'dart:convert';

import 'package:appnest_spec/appnest_spec.dart';
import 'package:crypto/crypto.dart';

/// Evidence for a creation-only declaration closure. Neither hash implies that
/// the provider authored the final requires list when capabilities were added.
class CompiledGeneratedCreation {
  final AppSpec spec;
  final String rawOutputHash, inputDefinitionHash;
  final List<String> addedCapabilities;

  CompiledGeneratedCreation._(
    this.spec,
    this.rawOutputHash,
    this.inputDefinitionHash,
    Iterable<String> added,
  ) : addedCapabilities = List.unmodifiable(added);

  Map<String, dynamic> toJson() => {
    'compiler': 'requiredCapabilities.v1',
    'rawOutputHash': rawOutputHash,
    'inputDefinitionHash': inputDefinitionHash,
    'candidateHash': spec.hash,
    'addedCapabilities': addedCapabilities,
  };
}

/// Only fresh generated creations may use this compiler. Published, manually
/// authored and edited specs continue through AppSpec.parse unchanged.
///
/// The strict parser derives its required capabilities after validating the
/// complete authored graph. Only that final, anchored diagnostic may trigger
/// closure; its names must be supported capabilities. No graph, policy, action,
/// rule, field, value or ID is inferred. Diagnostic drift fails closed. The
/// modified declaration is then parsed strictly again, including size limits.
CompiledGeneratedCreation compileGeneratedCreation(
  String source, {
  String? rawOutput,
}) {
  final raw = rawOutput ?? source;
  if (utf8.encode(raw).length > Limits.definitionBytes ||
      utf8.encode(source).length > Limits.definitionBytes) {
    throw const SpecException('Definition is too large');
  }
  final rawHash = sha256.convert(utf8.encode(raw)).toString();
  final inputHash = sha256.convert(utf8.encode(source)).toString();
  try {
    return CompiledGeneratedCreation._(
      AppSpec.parse(source),
      rawHash,
      inputHash,
      const [],
    );
  } on SpecException catch (error) {
    const prefix = 'Missing required capabilities: ';
    if (!error.message.startsWith(prefix)) rethrow;
    final missing = error.message.substring(prefix.length).split(', ');
    if (missing.isEmpty ||
        missing.toSet().length != missing.length ||
        missing.any((name) => !capabilities.contains(name)) ||
        error.message != '$prefix${missing.join(', ')}') {
      rethrow;
    }
    // Reaching the final parser diagnostic already validated the input shape,
    // explicit requires allowlist, graph references and all component options.
    final json = jsonDecode(source) as Map<String, dynamic>;
    final declared = List<String>.from(json['requires'] as List);
    if (missing.any(declared.contains)) rethrow;
    json['requires'] = [...declared, ...missing];
    final compiled = AppSpec.parse(jsonEncode(json));
    return CompiledGeneratedCreation._(
      compiled,
      rawHash,
      inputHash,
      missing,
    );
  }
}
