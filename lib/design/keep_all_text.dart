import 'package:flutter/material.dart';

final _hangul = RegExp(r'[가-힣]');

/// 한국어 어절 안에서는 줄을 바꾸지 않도록 글자 사이에 단어 결합자를 넣는다.
/// 영어처럼 띄어쓰기로만 줄을 바꾸는 글은 그대로 둔다.
String keepAll(String text) => text.replaceAllMapped(RegExp(r'\S+'), (match) {
  final word = match[0]!;
  return _hangul.hasMatch(word) ? word.characters.join('⁠') : word;
});

/// 어절 단위로 줄을 바꾸는 텍스트. 화면 낭독은 원문을 읽는다.
class KeepAllText extends StatelessWidget {
  const KeepAllText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(
    keepAll(data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    semanticsLabel: data,
  );
}
