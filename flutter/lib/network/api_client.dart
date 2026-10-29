import 'dart:convert';
import 'package:http/http.dart' as http;

/// HTTP client for the demo FastAPI server. The JWT is memory-only.
/// For Android over USB use `adb reverse tcp:8000 tcp:8000`.
class ApiClient {
  ApiClient(String baseUrl) : baseUrl = baseUrl.replaceAll(RegExp(r'/$'), '');
  final String baseUrl;
  String? _token;
  bool get loggedIn => _token != null;

  Future<void> register(String email, String password) async {
    await request('POST', '/api/auth/register', data: {
      'email': email.trim(), 'password': password,
    }, authenticated: false);
    await login(email, password);
  }

  Future<void> login(String email, String password) async {
    final result = await request('POST', '/api/auth/login', data: {
      'email': email.trim(), 'password': password,
    }, authenticated: false);
    if (result is! Map || result['access_token'] is! String) {
      throw const FormatException('Сервер не повернув токен доступу');
    }
    _token = result['access_token'] as String;
  }

  Future<dynamic> request(String method, String path, {
    Object? data, bool authenticated = true,
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Accept':'application/json'};
    if (data != null) headers['Content-Type'] = 'application/json';
    if (authenticated) {
      final token = _token;
      if (token == null) throw StateError('Спочатку увійди в обліковий запис');
      headers['Authorization'] = 'Bearer $token';
    }
    late final http.Response response;
    try {
      response = await http.Request(method, url).letSend(headers, data);
    } catch (e) {
      throw StateError('Не вдалося з’єднатися із сервером $baseUrl: $e');
    }
    dynamic body;
    try {
      body = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw StateError('Некоректна відповідь сервера (${response.statusCode})');
    }
    if (response.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      String description;
      if (detail is String) {
        description = detail;
      } else if (detail is List) {
        description = detail.map((e) => e is Map ? e['msg'] : e).join('; ');
      } else {
        description = 'HTTP ${response.statusCode}';
      }
      throw StateError('API ${response.statusCode}: $description');
    }
    return body;
  }
}

extension _HttpRequestSender on http.Request {
  Future<http.Response> letSend(Map<String, String> headers, Object? data) async {
    this.headers.addAll(headers);
    if (data != null) body = jsonEncode(data);
    final streamed = await send().timeout(const Duration(seconds: 12));
    return http.Response.fromStream(streamed).timeout(const Duration(seconds: 12));
  }
}
