const int maxLogMessageLength = 500;
const String _redactedValue = '[REDACTED]';

final RegExp _authorizationBearerPattern = RegExp(
  r'\bAuthorization\b\s*[:=]\s*Bearer\s+[A-Za-z0-9._~+/\-]+=*',
  caseSensitive: false,
);

final RegExp _genericSensitiveKeyValuePattern = RegExp(
  r'("?(?:access[_\s-]?token|refresh[_\s-]?token|id[_\s-]?token|client[_\s-]?secret|authorization|password|api[_\s-]?key|session[_\s-]?secret|decryption[_\s-]?key|cookie|set-cookie)"?)(\s*[:=]\s*)("(?:\\.|[^"\\])*"|[^\s,;}\]]+)',
  caseSensitive: false,
);

final RegExp _sensitiveQueryPattern = RegExp(
  r'([?&](?:access_token|refresh_token|id_token|token|client_secret|api_key|apikey|password|code|grant|sig|signature|x-amz-signature|x-amz-credential|x-amz-security-token|awsaccesskeyid|googleaccessid|policy|key-pair-id)=)[^&\s]+',
  caseSensitive: false,
);

final RegExp _bearerTokenPattern = RegExp(
  r'\bBearer\s+[A-Za-z0-9._~+/\-]+=*',
  caseSensitive: false,
);

final RegExp _decryptionKeyFlagPattern = RegExp(
  r'(-decryption_key\s+)[^\s]+',
  caseSensitive: false,
);

String truncateLogText(String value, {int maxLength = maxLogMessageLength}) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...[truncated]';
}

String redactSensitiveText(String value) {
  var redacted = value;

  redacted = redacted.replaceAllMapped(_authorizationBearerPattern, (_) {
    return 'Authorization: Bearer $_redactedValue';
  });

  redacted = redacted.replaceAllMapped(_genericSensitiveKeyValuePattern, (
    match,
  ) {
    final key = match.group(1) ?? '';
    final delimiter = match.group(2) ?? '=';
    return '$key$delimiter$_redactedValue';
  });

  redacted = redacted.replaceAllMapped(_sensitiveQueryPattern, (match) {
    final prefix = match.group(1) ?? '';
    return '$prefix$_redactedValue';
  });

  redacted = redacted.replaceAllMapped(_bearerTokenPattern, (_) {
    return 'Bearer $_redactedValue';
  });

  redacted = redacted.replaceAllMapped(_decryptionKeyFlagPattern, (match) {
    return '${match.group(1) ?? '-decryption_key '}$_redactedValue';
  });

  return redacted;
}
