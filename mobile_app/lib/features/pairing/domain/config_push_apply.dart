import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/result.dart';
import '../../sources/domain/photo_source.dart';
import '../../sources/domain/source_descriptor.dart';
import '../../sources/smb/smb_photo_source.dart';
import '../../sources/state/sources_providers.dart';

/// Applies the decrypted plaintext JSON payload of a config-push
/// (`ConfigPushConfirmationScreen.onAccept`, docs/PLAN.md point 9) as a new
/// configured source.
///
/// Only `"type": "smb"` payloads are supported today - matching what
/// `send_config_push_screen.dart` currently ever produces (see that file's
/// doc comment on why the payload shape is deliberately SMB-only for now).
/// Any other `type`, or a payload that fails to parse/validate at all,
/// returns an [Unsupported]/[Failure] result rather than throwing - this
/// runs right after end-to-end decryption of data that ultimately came from
/// another device via a relay server, so it must never crash the app on
/// malformed or unexpected input.
Future<Result<void>> applyDecryptedConfigPush(
  String plaintextJson, {
  required WidgetRef ref,
  String? senderLabel,
}) async {
  final Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(plaintextJson);
    if (decoded is! Map<String, dynamic>) {
      return Result.err(const Unsupported('Config-push payload is not a JSON object'));
    }
    payload = decoded;
  } on FormatException catch (e) {
    return Result.err(Unsupported('Config-push payload is not valid JSON', cause: e));
  }

  final type = payload['type'] as String?;
  switch (type) {
    case 'smb':
      return _applySmb(payload, ref: ref, senderLabel: senderLabel);
    case null:
      return Result.err(const Unsupported('Config-push payload is missing a "type" field'));
    default:
      return Result.err(Unsupported('Unsupported config-push payload type: "$type"'));
  }
}

Future<Result<void>> _applySmb(
  Map<String, dynamic> payload, {
  required WidgetRef ref,
  String? senderLabel,
}) async {
  final SmbSourceConfig config;
  try {
    config = SmbSourceConfig.fromJson(payload, password: payload['password'] as String? ?? '');
  } catch (e) {
    return Result.err(Unsupported('Malformed SMB config-push payload', cause: e));
  }

  if (config.host.isEmpty || config.share.isEmpty) {
    return Result.err(const Unsupported('SMB config-push payload is missing "host"/"share"'));
  }

  final id = ref.read(sourceIdGeneratorProvider).v4();
  final displayName = senderLabel == null || senderLabel.isEmpty
      ? 'Von Handy empfangen: ${config.host}/${config.share}'
      : 'Von $senderLabel empfangen: ${config.host}/${config.share}';

  final descriptor = SourceDescriptor(
    type: SourceType.smb,
    id: id,
    displayName: displayName,
    config: config.toJson(),
  );

  final source = fromDescriptor(descriptor, password: config.password);

  try {
    await ref.read(sourcesProvider.notifier).add(source);
  } catch (e) {
    return Result.err(Unsupported('Failed to register received SMB source', cause: e));
  }

  return Result.ok(null);
}
