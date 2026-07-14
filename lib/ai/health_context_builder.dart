import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/health_repository.dart';
import 'ai_models.dart';

class HealthContextEnvelope {
  const HealthContextEnvelope({
    required this.json,
    required this.sha256,
    required this.byteLength,
    required this.estimatedTokens,
  });

  final String json;
  final String sha256;
  final int byteLength;
  final int estimatedTokens;
}

class HealthContextBuilder {
  HealthContextBuilder(this._repository);

  final HealthRepository _repository;

  Future<HealthContextEnvelope> build(String profileId) async {
    final snapshot = await _repository.completeProfileSnapshot(profileId);
    final json = HealthRepository.stableJson(snapshot);
    final bytes = utf8.encode(json);
    final stableContent = HealthRepository.stableJson({
      'schema_version': snapshot['schema_version'],
      'active_profile_id': snapshot['active_profile_id'],
      'manifest': snapshot['manifest'],
      'data': snapshot['data'],
    });
    return HealthContextEnvelope(
      json: json,
      sha256: sha256.convert(utf8.encode(stableContent)).toString(),
      byteLength: bytes.length,
      // A conservative display estimate. Providers remain authoritative.
      estimatedTokens: (bytes.length / 3.5).ceil(),
    );
  }

  void ensureFits({
    required HealthContextEnvelope context,
    required ModelCapabilities capabilities,
    required int maxOutputTokens,
    int promptReserveTokens = 3000,
  }) {
    final limit = capabilities.contextWindowTokens;
    if (limit == null) return;
    final required =
        context.estimatedTokens + maxOutputTokens + promptReserveTokens;
    if (required > limit) {
      throw StateError(
        'The complete profile needs about $required tokens but this model has a '
        '$limit-token context window. No health data was truncated; choose a '
        'larger-context model.',
      );
    }
  }
}
