import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/custom_endpoint_rules.dart';

void main() {
  group('checkCustomEndpointUrl', () {
    test('accepts https for any host', () {
      final check = checkCustomEndpointUrl('https://llm.example.com/v1');
      expect(check.isValid, isTrue);
      expect(check.uri!.host, 'llm.example.com');
    });

    test('accepts http on this device and in the local network', () {
      for (final url in [
        'http://localhost:1234/v1',
        'http://127.0.0.1:11434/v1',
        'http://[::1]:1234/v1',
        'http://mac-studio.local:1234/v1',
        'http://192.168.1.20:1234/v1',
        'http://10.0.0.5:1234/v1',
        'http://172.16.0.9:1234/v1',
        'http://172.31.255.1:1234/v1',
        'http://169.254.10.10:1234/v1',
        'http://[fd12:3456::1]:1234/v1',
        'http://[fe80::1]:1234/v1',
      ]) {
        expect(checkCustomEndpointUrl(url).isValid, isTrue, reason: url);
      }
    });

    test('refuses plain http to a public host', () {
      for (final url in [
        'http://8.8.8.8/v1',
        'http://172.32.0.1/v1',
        'http://api.example.com/v1',
        'http://[2001:db8::1]/v1',
      ]) {
        final check = checkCustomEndpointUrl(url);
        expect(check.isValid, isFalse, reason: url);
        expect(
          check.problem,
          CustomEndpointUrlProblem.httpToRemoteHost,
          reason: url,
        );
      }
    });

    test('refuses empty input and non-http addresses', () {
      expect(
        checkCustomEndpointUrl('').problem,
        CustomEndpointUrlProblem.empty,
      );
      expect(
        checkCustomEndpointUrl('   ').problem,
        CustomEndpointUrlProblem.empty,
      );
      expect(
        checkCustomEndpointUrl('localhost:1234/v1').problem,
        CustomEndpointUrlProblem.invalid,
      );
      expect(
        checkCustomEndpointUrl('ftp://host/v1').problem,
        CustomEndpointUrlProblem.invalid,
      );
    });

    test('refuses credentials, query and fragment', () {
      expect(
        checkCustomEndpointUrl('https://user:pw@host/v1').problem,
        CustomEndpointUrlProblem.credentialsOrQuery,
      );
      expect(
        checkCustomEndpointUrl('https://host/v1?key=1').problem,
        CustomEndpointUrlProblem.credentialsOrQuery,
      );
      expect(
        checkCustomEndpointUrl('https://host/v1#x').problem,
        CustomEndpointUrlProblem.credentialsOrQuery,
      );
    });
  });

  test('customEndpointNetworkOf sorts hosts into device, lan and remote', () {
    expect(customEndpointNetworkOf('localhost'), CustomEndpointNetwork.device);
    expect(customEndpointNetworkOf('127.10.2.3'), CustomEndpointNetwork.device);
    expect(customEndpointNetworkOf('::1'), CustomEndpointNetwork.device);
    expect(customEndpointNetworkOf('mac.local'), CustomEndpointNetwork.lan);
    expect(customEndpointNetworkOf('192.168.1.20'), CustomEndpointNetwork.lan);
    expect(customEndpointNetworkOf('10.255.0.1'), CustomEndpointNetwork.lan);
    expect(customEndpointNetworkOf('172.20.0.1'), CustomEndpointNetwork.lan);
    expect(customEndpointNetworkOf('169.254.0.1'), CustomEndpointNetwork.lan);
    expect(customEndpointNetworkOf('fc00::1'), CustomEndpointNetwork.lan);
    expect(customEndpointNetworkOf('fe80::1'), CustomEndpointNetwork.lan);
    expect(customEndpointNetworkOf('128.0.0.1'), CustomEndpointNetwork.remote);
    expect(customEndpointNetworkOf('172.15.0.1'), CustomEndpointNetwork.remote);
    expect(
      customEndpointNetworkOf('evil-localhost.com'),
      CustomEndpointNetwork.remote,
    );
    expect(
      customEndpointNetworkOf('fdx.example.com'),
      CustomEndpointNetwork.remote,
    );
  });

  test('plain http warning is only for http on the local network', () {
    expect(
      customEndpointPlainHttpOnLan(Uri.parse('http://192.168.1.20:1234/v1')),
      isTrue,
    );
    expect(
      customEndpointPlainHttpOnLan(Uri.parse('http://localhost:1234/v1')),
      isFalse,
    );
    expect(
      customEndpointPlainHttpOnLan(Uri.parse('https://192.168.1.20/v1')),
      isFalse,
    );
  });

  test('network notice names the receiving host only for remote servers', () {
    final device = customEndpointNetworkNotice(
      Uri.parse('http://localhost/v1'),
    );
    expect(device.network, CustomEndpointNetwork.device);
    expect(device.host, isNull);

    final lan = customEndpointNetworkNotice(
      Uri.parse('http://192.168.1.20/v1'),
    );
    expect(lan.network, CustomEndpointNetwork.lan);
    expect(lan.host, isNull);

    final remote = customEndpointNetworkNotice(
      Uri.parse('https://api.example.com/v1'),
    );
    expect(remote.network, CustomEndpointNetwork.remote);
    expect(remote.host, 'api.example.com');
  });

  test('customEndpointUrl drops a trailing slash of the base path', () {
    expect(
      customEndpointUrl(
        Uri.parse('http://localhost:1234/v1/'),
        '/models',
      ).toString(),
      'http://localhost:1234/v1/models',
    );
    expect(
      customEndpointUrl(
        Uri.parse('http://localhost:1234/v1'),
        '/audio/transcriptions',
      ).toString(),
      'http://localhost:1234/v1/audio/transcriptions',
    );
  });

  test('customEndpointReady needs an address and a model, not a key', () {
    expect(
      customEndpointReady(url: 'http://localhost:1234/v1', model: 'llama'),
      isTrue,
    );
    expect(
      customEndpointReady(url: 'http://localhost:1234/v1', model: '  '),
      isFalse,
    );
    expect(customEndpointReady(url: 'nope', model: 'llama'), isFalse);
  });

  test('customEndpointHttpClass names the class of each status', () {
    expect(
      customEndpointHttpClass(401, ''),
      CustomEndpointHttpClass.unauthorized,
    );
    expect(
      customEndpointHttpClass(403, ''),
      CustomEndpointHttpClass.unauthorized,
    );
    expect(
      customEndpointHttpClass(500, ''),
      CustomEndpointHttpClass.serverError,
    );
    expect(
      customEndpointHttpClass(404, 'model not found'),
      CustomEndpointHttpClass.modelMissing,
    );
    expect(
      customEndpointHttpClass(400, 'the model x does not exist'),
      CustomEndpointHttpClass.modelMissing,
    );
    expect(
      customEndpointHttpClass(404, 'Not Found'),
      CustomEndpointHttpClass.badFormat,
    );
    expect(
      customEndpointHttpClass(400, 'bad input'),
      CustomEndpointHttpClass.badFormat,
    );
    expect(customEndpointHttpClass(418, ''), CustomEndpointHttpClass.badFormat);
  });

  group('IPv4 literals with leading zeros', () {
    test('are not taken for a local address, so plain http is refused', () {
      // glibc resolves 010.0.0.1 to 8.0.0.1 (a public address) and
      // 0172.16.0.1 to 122.16.0.1, while a decimal reading would call both
      // local. Such literals count as remote: https only.
      expect(
        customEndpointNetworkOf('010.0.0.1'),
        CustomEndpointNetwork.remote,
      );
      expect(
        customEndpointNetworkOf('0172.16.0.1'),
        CustomEndpointNetwork.remote,
      );
      expect(
        checkCustomEndpointUrl('http://010.0.0.1:1234/v1').problem,
        CustomEndpointUrlProblem.httpToRemoteHost,
      );
    });

    test('canonical private literals keep their local-network class', () {
      expect(
        customEndpointNetworkOf('192.168.1.20'),
        CustomEndpointNetwork.lan,
      );
      expect(
        customEndpointNetworkOf('127.0.0.1'),
        CustomEndpointNetwork.device,
      );
    });
  });
}
