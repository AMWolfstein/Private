import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/log_redaction.dart';

void main() {
  group('truncateLogText', () {
    test('keeps text at or under the limit unchanged', () {
      expect(truncateLogText('short'), 'short');
      expect(truncateLogText('abc', maxLength: 3), 'abc');
      expect(
        truncateLogText('x' * maxLogMessageLength),
        'x' * maxLogMessageLength,
      );
    });

    test('cuts longer text at the limit and marks it truncated', () {
      expect(truncateLogText('abcdef', maxLength: 3), 'abc...[truncated]');
      final long = 'y' * (maxLogMessageLength + 1);
      expect(
        truncateLogText(long),
        '${'y' * maxLogMessageLength}...[truncated]',
      );
    });
  });

  group('redactSensitiveText', () {
    test('redacts an Authorization bearer header', () {
      final out = redactSensitiveText('Authorization: Bearer abc.def-123==');
      expect(out, contains('[REDACTED]'));
      expect(out, isNot(contains('abc.def-123')));
    });

    test('redacts sensitive query parameters and keeps the rest', () {
      expect(
        redactSensitiveText('https://example.test/a?token=abc123&page=2'),
        'https://example.test/a?token=[REDACTED]&page=2',
      );
      expect(
        redactSensitiveText('https://example.test/cb?code=xyz&state=ok'),
        'https://example.test/cb?code=[REDACTED]&state=ok',
      );
    });

    test('redacts signed storage URL parameters', () {
      final out = redactSensitiveText(
        'https://bucket.test/o?X-Amz-Signature=deadbeef&X-Amz-Credential=cred',
      );
      expect(out, isNot(contains('deadbeef')));
      expect(out, isNot(contains('=cred')));
      expect(out, contains('X-Amz-Signature=[REDACTED]'));
      expect(out, contains('X-Amz-Credential=[REDACTED]'));
    });

    test('redacts a quoted JSON value for a sensitive key', () {
      expect(
        redactSensitiveText('{"api_key": "secret-value", "name": "ok"}'),
        '{"api_key": [REDACTED], "name": "ok"}',
      );
    });

    test('redacts unquoted key=value and key: value pairs', () {
      expect(redactSensitiveText('password: hunter2'), 'password: [REDACTED]');
      expect(
        redactSensitiveText('refresh_token=rt-1 next=2'),
        'refresh_token=[REDACTED] next=2',
      );
      expect(
        redactSensitiveText('client-secret = s3cr3t;'),
        'client-secret = [REDACTED];',
      );
    });

    test('redacts a bare Bearer token', () {
      expect(
        redactSensitiveText('token sent as Bearer abc.def'),
        'token sent as Bearer [REDACTED]',
      );
    });

    test('redacts the value of a -decryption_key flag', () {
      expect(
        redactSensitiveText('ffmpeg -decryption_key 0a1b2c --verbose'),
        'ffmpeg -decryption_key [REDACTED] --verbose',
      );
    });

    test('leaves ordinary text unchanged', () {
      const plain = 'Scanned 12 of 40 files in /music/Artist/Album';
      expect(redactSensitiveText(plain), plain);
      expect(redactSensitiveText(''), '');
      expect(
        redactSensitiveText('the token count is high'),
        'the token count is high',
      );
    });
  });
}
