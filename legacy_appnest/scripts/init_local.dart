import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Generates only ignored local secrets; never overwrites an existing file.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final target = File('${root.path}/appnest_server/config/passwords.yaml');
  if (await target.exists()) {
    stdout.writeln(
      'Local secret configuration already exists; left unchanged.',
    );
    return;
  }
  final random = Random.secure();
  String secret() =>
      base64Url.encode(List.generate(64, (_) => random.nextInt(256)));
  final text = StringBuffer('# Generated local-only secrets. Do not commit.\n');
  for (final mode in ['development', 'test']) {
    text.writeln('$mode:');
    for (final key in [
      'database',
      'serviceSecret',
      'emailSecretHashPepper',
      'jwtHmacSha512PrivateKey',
      'jwtRefreshTokenHashPepper',
    ]) {
      text.writeln('  $key: "${secret()}"');
    }
  }
  await target.create(exclusive: true);
  await target.writeAsString(text.toString());
  if (!Platform.isWindows) await Process.run('chmod', ['600', target.path]);
  stdout.writeln(
    'Created ignored development/test secrets. No AI provider configured.',
  );
}
