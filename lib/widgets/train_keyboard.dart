// lib/widgets/train_keyboard.dart
//
// 12306 风格车次键盘（基线 pages/train/keyboard.vue 1:1 移植——Phase 4 清单第 1 项）：
//   行1: [G][D][1][2][3]   行2: [C][K][4][5][6]
//   行3: [L][T][7][8][9]   行4: [Z][Y][S][0][⌫]
//   语义：字母键 = 前缀替换（已有字母前缀则替换，否则前置）；数字键 = 追加；⌫ = 删除末位。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TrainKeyboard extends StatelessWidget {
  const TrainKeyboard({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onConfirm,
    this.maxDigits = 6,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onConfirm;

  /// 数字部分最大位数（车次号最长数字段）
  final int maxDigits;

  static const _letters = <List<String>>[
    ['G', 'D'],
    ['C', 'K'],
    ['L', 'T'],
    ['Z', 'Y', 'S'],
  ];

  bool _isLetter(String c) => RegExp(r'^[A-Z]$').hasMatch(c.toUpperCase());

  void _onLetter(String letter) {
    // 前缀替换语义（基线 keyboard.vue onLetterClick）
    if (value.isEmpty || !_isLetter(value[0])) {
      onChanged(letter + value);
    } else {
      onChanged(letter + value.substring(1));
    }
    HapticFeedback.selectionClick();
  }

  void _onDigit(String digit) {
    final digits = value.replaceAll(RegExp(r'^[A-Z]'), '');
    if (digits.length >= maxDigits) return;
    onChanged(value + digit);
    HapticFeedback.selectionClick();
  }

  void _onDelete() {
    if (value.isNotEmpty) onChanged(value.substring(0, value.length - 1));
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // RTL 审查（审计 §8）：确认键贴"文本结束侧"，用方向感知 API
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 8, bottom: 6),
            child: FilledButton(onPressed: onConfirm, child: const Text('确认')),
          ),
        ),
        for (var row = 0; row < 4; row++)
          Row(
            children: [
              for (final letter in _letters[row])
                _key(letter, () => _onLetter(letter), cs),
              for (var col = 0; col < 5 - _letters[row].length; col++)
                ..._buildRowTail(row, col, cs),
            ],
          ),
      ]),
    );
  }

  List<Widget> _buildRowTail(int row, int col, ColorScheme cs) {
    // 行4 第4列 = 数字0，第5列 = ⌫；其余行纯数字
    if (row == 3 && col == 1) {
      return [_key('⌫', _onDelete, cs, isDelete: true)];
    }
    final digit = switch (row) {
      0 => (col + 1).toString(),
      1 => (col + 4).toString(),
      2 => (col + 7).toString(),
      _ => '0',
    };
    return [_key(digit, () => _onDigit(digit), cs)];
  }

  Widget _key(String label, VoidCallback onTap, ColorScheme cs,
      {bool isDelete = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: isDelete ? cs.errorContainer : cs.surface,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 46,
              child: Center(
                child: isDelete
                    ? Icon(Icons.backspace_outlined, color: cs.onErrorContainer)
                    : Text(label,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
