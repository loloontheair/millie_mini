import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

/// Home Depot product search through the Apify MCP server (mcp.apify.com).
/// One actor is exposed as a tool; we discover its MCP name at first use.
class ApifyService {
  ApifyService(this._storage);

  final StorageService _storage;

  static const actor = 'cirkit/home-depot-product-scraper';
  static const storeId = '0667'; // Rancho Mirage, CA - nearest store to 92260
  static const zipCode = '92260';
  static final _endpoint = Uri.parse('https://mcp.apify.com?tools=$actor');

  String? _sessionId;
  String? _toolName;
  int _nextId = 1;

  Future<bool> get isConfigured async => ((await _storage.getApiKey('apify')) ?? '').isNotEmpty;

  Future<String> searchHomeDepot(String query, {int maxItems = 5}) async {
    final token = await _storage.getApiKey('apify');
    if (token == null || token.isEmpty) {
      return 'Store search is not configured: add the Apify token in AI Service Settings.';
    }
    try {
      _toolName ??= await _connect(token);
      final result = await _rpc(token, 'tools/call', {
        'name': _toolName,
        'arguments': {
          'keywords': [query],
          'storeId': storeId,
          'zipCode': zipCode,
          'maxItems': maxItems,
          'maxItemsPerKeyword': maxItems,
        },
      });
      return _compact(result);
    } catch (e) {
      debugPrint('Apify search failed: $e');
      _toolName = null;
      _sessionId = null;
      return 'Store search failed: $e';
    }
  }

  Future<String> _connect(String token) async {
    await _rpc(token, 'initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'millie-mini', 'version': '1.0'},
    });
    await _post(token, {'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    final list = await _rpc(token, 'tools/list', {});
    final tools = (list['tools'] as List?) ?? [];
    final match = tools.cast<Map>().firstWhere(
      (t) => (t['name'] as String).contains('home-depot-product-scraper'),
      orElse: () => tools.isEmpty ? throw StateError('no tools exposed') : tools.first as Map,
    );
    return match['name'] as String;
  }

  Future<Map<String, dynamic>> _rpc(String token, String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final msg = await _post(token, {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}, waitForId: id);
    if (msg['error'] != null) throw StateError(jsonEncode(msg['error']));
    return (msg['result'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _post(String token, Map<String, dynamic> body, {int? waitForId}) async {
    final res = await http
        .post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            if (_sessionId != null) 'mcp-session-id': _sessionId!,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120)); // actor runs take 20-60 s
    _sessionId = res.headers['mcp-session-id'] ?? _sessionId;
    if (res.statusCode >= 300) throw StateError('HTTP ${res.statusCode}: ${res.body}');
    if (waitForId == null) return {};
    final text = utf8.decode(res.bodyBytes);
    if ((res.headers['content-type'] ?? '').contains('text/event-stream')) {
      for (final line in text.split('\n')) {
        if (!line.startsWith('data:')) continue;
        final msg = jsonDecode(line.substring(5).trim());
        if (msg is Map && msg['id'] == waitForId) return msg.cast<String, dynamic>();
      }
      throw StateError('no response for id $waitForId');
    }
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  /// Turn the MCP result into a short text the LLM can speak from.
  static String _compact(Map<String, dynamic> result) {
    final texts = ((result['content'] as List?) ?? [])
        .whereType<Map>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .toList();
    List items = [];
    for (final t in texts) {
      try {
        final decoded = jsonDecode(t);
        if (decoded is List) items.addAll(decoded);
        if (decoded is Map && decoded['items'] is List) items.addAll(decoded['items']);
      } catch (_) {}
    }
    if (items.isEmpty) {
      final raw = texts.join('\n');
      return raw.isEmpty ? 'No products found.' : raw.substring(0, raw.length.clamp(0, 2000));
    }
    return items.whereType<Map>().map((p) {
      final stock = p['inStock'] ?? p['inventory'] ?? p['availability'] ?? p['storeAvailability'];
      return '- ${p['title'] ?? p['name']}: \$${p['price']}'
          '${p['brand'] != null ? ' (${p['brand']})' : ''}'
          '${stock != null ? ', availability: $stock' : ''}'
          '${p['itemId'] != null ? ', item ${p['itemId']}' : ''}';
    }).join('\n');
  }
}
