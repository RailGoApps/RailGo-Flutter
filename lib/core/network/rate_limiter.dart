// lib/core/network/rate_limiter.dart
//
// API 限速合规（api.railgo.dev §使用限制，2026-09-25 复核：
// 服务方未设 key、未设显式限速，但"肆意抓取可能被 CDN 屏蔽或封禁 IP"）。
//  - 每服务源独立令牌桶（默认 2 req/s，突发 4）
//  - 全局并发闸门（同时最多 4 个在途请求）
//  - 预选词等高频场景的防抖由 UI 层调用 [debounce] 完成
library;

import 'dart:async';

class TokenBucket {
  TokenBucket({this.ratePerSecond = 2, this.burst = 4})
      : _tokens = burst.toDouble(),
        _mono = Stopwatch()..start();

  final double ratePerSecond;
  final int burst;
  double _tokens;
  // 审计 B-01：改用单调时钟。墙钟回拨会让"流逝时间"恒 ≤0，
  // 令牌永不补充（自锁）或被人为回拨刷桶（WAF 合规失效）。
  final Stopwatch _mono;
  int _lastElapsedUs = 0;
  final List<Completer<void>> _waiters = [];

  void _refill() {
    final us = _mono.elapsedMicroseconds;
    final elapsed = (us - _lastElapsedUs) / 1e6;
    if (elapsed <= 0) return;
    _lastElapsedUs = us;
    _tokens = (_tokens + elapsed * ratePerSecond).clamp(0, burst.toDouble());
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
