// Interop tests against the real `curl` binary over FTPS.
//
// Dart's own client starts the data-connection TLS handshake immediately,
// so the tests in ftps_test.dart can miss client-order problems. curl is a
// widely used FTPS client; these tests run it in passive and active mode,
// over explicit and implicit FTPS, with a generated self-signed certificate.
//
// Skipped when curl is not installed or lacks FTPS support, and on Windows
// (Schannel-based curl and runner firewall rules make active mode unreliable
// there).
import 'dart:io';
import 'dart:math';

import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _user = 'curluser';
const _pass = 'curlpass';

Future<String?> _skipReason() async {
  if (Platform.isWindows) return 'curl FTPS tests are not run on Windows';
  try {
    final result = await Process.run('curl', ['--version']);
    if (result.exitCode != 0) return 'curl --version failed';
    final protocols = (result.stdout as String)
        .split('\n')
        .firstWhere((l) => l.startsWith('Protocols:'), orElse: () => '');
    if (!protocols.split(' ').contains('ftps')) {
      return 'curl was built without FTPS support';
    }
    return null;
  } on ProcessException {
    return 'curl is not installed';
  }
}

/// Directory listings end when the server closes the data connection.
/// dart:io never sends a TLS close_notify before closing
/// (https://github.com/dart-lang/sdk/issues/64816), and curl built with
/// OpenSSL 3 reports that as "unexpected eof while reading". Downloads and
/// uploads are not affected because curl knows their size.
Future<String?> _listingSkipReason() async {
  final result = await Process.run('curl', ['--version']);
  final version = (result.stdout as String).split('\n').first;
  if (version.contains('OpenSSL/3')) {
    return 'curl uses OpenSSL 3, which rejects a TLS stream closed without '
        'close_notify; dart:io never sends one (dart-lang/sdk#64816)';
  }
  return null;
}

/// Runs curl with TLS verification off (self-signed certificate) and fails
/// the test with curl's stderr if curl exits non-zero.
Future<ProcessResult> _curl(List<String> args) async {
  final result = await Process.run(
    'curl',
    ['--silent', '--show-error', '--insecure', '--max-time', '20', ...args],
    stdoutEncoding: null,
  );
  expect(result.exitCode, 0,
      reason: 'curl ${args.join(' ')} failed: ${result.stderr}');
  return result;
}

void main() async {
  final skip = await _skipReason();
  final listingSkip = skip == null ? await _listingSkipReason() : null;

  late Directory root;
  late Directory local;
  late List<int> binary;
  final cert = SelfSignedCertificate.generate();

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('ftps_curl_root_');
    local = Directory.systemTemp.createTempSync('ftps_curl_local_');
    File(p.join(root.path, 'hello.txt')).writeAsStringSync('Hello, FTPS!\n');
    final random = Random(42);
    binary = List<int>.generate(256 * 1024, (_) => random.nextInt(256));
    File(p.join(root.path, 'data.bin')).writeAsBytesSync(binary);
  });

  tearDownAll(() {
    root.deleteSync(recursive: true);
    local.deleteSync(recursive: true);
  });

  group('curl, explicit FTPS', () {
    const port = 2280;
    late FtpServer server;
    const base = 'ftp://127.0.0.1:$port';
    const auth = ['--ssl-reqd', '--user', '$_user:$_pass'];

    setUpAll(() async {
      server = FtpServer(
        port,
        username: _user,
        password: _pass,
        fileOperations: PhysicalFileOperations(root.path),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.explicit,
        tlsConfig: cert.toTlsConfig(),
        logFunction: (_) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() => server.stop());

    test('lists the directory (passive)', () async {
      final result = await _curl([...auth, '$base/']);
      final listing = String.fromCharCodes(result.stdout as List<int>);
      expect(listing, contains('hello.txt'));
      expect(listing, contains('data.bin'));
    }, skip: listingSkip);

    test('downloads a text file', () async {
      final result = await _curl([...auth, '$base/hello.txt']);
      expect(
          String.fromCharCodes(result.stdout as List<int>), 'Hello, FTPS!\n');
    });

    test('downloads a binary file byte for byte', () async {
      final out = p.join(local.path, 'data.bin');
      await _curl([...auth, '--output', out, '$base/data.bin']);
      expect(File(out).readAsBytesSync(), binary);
    });

    test('uploads a file', () async {
      final src = File(p.join(local.path, 'upload.txt'))
        ..writeAsStringSync('uploaded with curl\n');
      await _curl([...auth, '--upload-file', src.path, '$base/upload.txt']);
      expect(File(p.join(root.path, 'upload.txt')).readAsStringSync(),
          'uploaded with curl\n');
    });

    test('lists the directory in active mode (PORT)', () async {
      final result = await _curl(
          [...auth, '--ftp-port', '127.0.0.1', '--disable-eprt', '$base/']);
      expect(String.fromCharCodes(result.stdout as List<int>),
          contains('hello.txt'));
    }, skip: listingSkip);

    test('downloads in active mode (PORT)', () async {
      final out = p.join(local.path, 'data_active.bin');
      await _curl([
        ...auth,
        '--ftp-port',
        '127.0.0.1',
        '--disable-eprt',
        '--output',
        out,
        '$base/data.bin',
      ]);
      expect(File(out).readAsBytesSync(), binary);
    });
  }, skip: skip);

  group('curl, implicit FTPS', () {
    const port = 2281;
    late FtpServer server;
    const base = 'ftps://127.0.0.1:$port';
    const auth = ['--user', '$_user:$_pass'];

    setUpAll(() async {
      server = FtpServer(
        port,
        username: _user,
        password: _pass,
        fileOperations: PhysicalFileOperations(root.path),
        serverType: ServerType.readAndWrite,
        securityMode: FtpSecurityMode.implicit,
        tlsConfig: cert.toTlsConfig(),
        logFunction: (_) {},
      );
      await server.startInBackground();
    });

    tearDownAll(() => server.stop());

    test('lists the directory', () async {
      final result = await _curl([...auth, '$base/']);
      expect(String.fromCharCodes(result.stdout as List<int>),
          contains('hello.txt'));
    }, skip: listingSkip);

    test('downloads a binary file byte for byte', () async {
      final out = p.join(local.path, 'data_implicit.bin');
      await _curl([...auth, '--output', out, '$base/data.bin']);
      expect(File(out).readAsBytesSync(), binary);
    });
  }, skip: skip);
}
