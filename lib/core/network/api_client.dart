// lib/core/network/api_client.dart
//
// 统一 Dio 客户端：
//  - 按服务源路由 base URL（service_source_<code> 优先，回退缺省域名）
//  - 令牌桶限流 + 全局并发闸门（WAF 合规）
//  - 短请求体防护（基线教训：axios 系适配器对空/极短请求体易出错——
//    本层保证 GET 不携带 body，POST 显式 FormData，Content-Length 由 Dio 正确处理）
library;

import 'package:dio/dio.dart';

import 'service_registry.dart';
import 'rate_limiter.dart';

typedef BaseUrlResolver = String Function(String serviceCode);

class RailGoApiClient {
  RailGoApiClient({
    Dio? dio,
    BaseUrlResolver? resolveBase,
    TokenBucket? bucket,
    ConcurrencyGate? gate,
  })  : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'User-Agent': 'RailGo-Flutter/3.0'},
        )),
        _resolveBase = resolveBase,
        _bucket = bucket,
        _gate = gate ?? ConcurrencyGate(4);

  final Dio _dio;
  final BaseUrlResolver? _resolveBase;
  final TokenBucket? _bucket;
  final ConcurrencyGate _gate;

  String baseFor(String code) {
    final override = _resolveBase?.call(code);
    if (override != null && override.isNotEmpty) return override;
    final meta = kServiceCatalog[code];
    if (meta == null) throw ArgumentError('unknown service code: $code');
    return meta.defaultBase;
  }

  Future<Response<T>> get<T>(
    String serviceCode,
    String path, {
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    final uri = '${baseFor(serviceCode)}$path';
    if (_bucket != null) await _bucket.acquire();
    return _gate.run(() => _dio.get<T>(
          uri,
          queryParameters: query,
          // 短请求体防护：GET 一律无 body
          options: options,
        ));
  }

  Future<Response<T>> postForm<T>(
    String serviceCode,
    String path, {
    Map<String, dynamic>? fields,
  }) async {
    final uri = '${baseFor(serviceCode)}$path';
    if (_bucket != null) await _bucket.acquire();
    return _gate.run(() => _dio.post<T>(
          uri,
          data: fields,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        ));
  }

  /// 固定主机端点（鉴权 center.zenglingkun.cn、tp 图床、赞助/反馈、12306、idcmoss 图库等）。
  /// 这些不属于 15 服务源体系，直接传完整 URI。
  Future<Response<T>> getAbsolute<T>(String uri, {Map<String, dynamic>? query}) async {
    if (_bucket != null) await _bucket.acquire();
    return _gate.run(() => _dio.get<T>(uri, queryParameters: query));
  }

  /// 固定主机表单 POST（配属查询 trainAssignment 等）
  Future<Response<T>> postFormAbsolute<T>(String uri, {Map<String, dynamic>? fields}) async {
    if (_bucket != null) await _bucket.acquire();
    return _gate.run(() => _dio.post<T>(
          uri,
          data: fields,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        ));
  }
}
