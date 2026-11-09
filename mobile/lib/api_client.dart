import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const _storage = FlutterSecureStorage();
  static const _configuredUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001/api',
  );
  static final _baseUri = _resolveBaseUri();

  static Uri _resolveBaseUri() {
    final url = kIsWeb
        ? const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://localhost:3001/api',
          )
        : _configuredUrl;
    final uri = Uri.parse(url);
    if (kReleaseMode && (uri.scheme != 'https' || uri.host.isEmpty)) {
      throw StateError('Production builds require an HTTPS API_BASE_URL.');
    }
    return uri;
  }

  final http.Client _client;
  String? _token;

  bool get hasToken => _token != null;

  Uri _uri(String path, {Map<String, String>? query}) {
    final basePath =
        _baseUri.path.endsWith('/') ? _baseUri.path : '${_baseUri.path}/';
    final relativePath = path.startsWith('/') ? path.substring(1) : path;
    return _baseUri.replace(
        path: '$basePath$relativePath', queryParameters: query);
  }

  Future<void> restoreToken() async {
    _token = await _storage.read(key: 'access_token');
  }

  Future<void> storeToken(String token) async {
    _token = token;
    await _storage.write(key: 'access_token', value: token);
  }

  Future<void> clearToken() async {
    _token = null;
    await _storage.delete(key: 'access_token');
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    final response =
        await _client.get(_uri(path, query: query), headers: _headers());
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    final response = await _client.put(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final response = await _client.patch(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, String> _headers({bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  dynamic _decode(http.Response response) {
    dynamic payload;
    if (response.body.isNotEmpty) {
      try {
        payload = jsonDecode(response.body);
      } on FormatException {
        throw ApiException(
            'Server returned an invalid response (${response.statusCode})');
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = payload is Map<String, dynamic>
          ? (payload['error'] as String? ??
              'Request failed (${response.statusCode})')
          : 'Request failed (${response.statusCode})';
      throw ApiException(message);
    }
    return payload;
  }
}
