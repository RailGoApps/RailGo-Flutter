// lib/core/network/rate_limiter.dart
//
// API 限速合规（基线 llms.txt §使用限制：2026.08.08 起启用限速，过快会被封 IP / WAF 黑名单）。
//  - 每服务源独立令牌桶（默认 2 req/s，突发 4）
//  - 全局并发闸门（同时最多 4 个在途请求）
//  - 预选词等高频场景的防抖由 UI 层调用 [debounce] 完成
library;

import 'dart:async';

class TokenBucket {
  TokenBucket({this.ratePerSecond = 2, this.burst = 4})
      : _tokens = burst.toDouble(),
        _lastRefill = DateTime.now();

  final double ratePerSecond;
  final int burst;
  double _tokens;
  DateTime _lastRefill;
  final List<Completer<void>> _waiters = [];

  void _refill() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRefill).inMicroseconds / 1e6;
    if (elapsed <= 0) return;
    _tokens = (_tokens + elapsed * ratePerSecond).clamp(0, burst.toDouble());
    _lastRefill = now;
  }

  Future<void> acquire() {
    _refill();
    if (_tokens >= 1) {
      _tokens -= 1;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    if (_waiters.length == 1) {
      _scheduleDrain();
    }
    return completer.future;
  }

  void _scheduleDrain() {
    final need = (1 - _tokens) / ratePerSecond;
    Timer(Duration(microseconds: (need * 1e6).ceil()), () {
      _refill();
      while (_waiters.isNotEmpty && _tokens >= 1) {
        _tokens -= 1;
        _waiters.removeAt(0).complete();
      }
      if (_waiters.isNotEmpty) _scheduleDrain();
    });
  }
}

class ConcurrencyGate {
  ConcurrencyGate(this.maxConcurrent)
      : _active = 0,
        _queue = [];

  final int maxConcurrent;
  int _active;
  final List<Completer<void>> _queue;

  Future<void> enter() {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future.then((_) {
      _active++;
    });
  }

  void leave() {
    _active--;
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    }
  }

  Future<T> run<T>(Future<T> Function() task) async {
    await enter();
    try {
      return await task();
    } finally {
      leave();
    }
  }
}

/// 简单防抖（预选词输入等场景；基线 train/query.vue 实证 260ms）
class Debouncer {
  Debouncer(this.delay);
  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}
