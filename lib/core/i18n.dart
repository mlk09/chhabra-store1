import 'package:flutter/widgets.dart';

enum AppLanguage { en, hi }

/// Makes the current language available to every widget below it.
class LangScope extends InheritedWidget {
  const LangScope({super.key, required this.language, required super.child});

  final AppLanguage language;

  static AppLanguage of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LangScope>()?.language ?? AppLanguage.en;

  @override
  bool updateShouldNotify(LangScope oldWidget) => language != oldWidget.language;
}

extension Tr on BuildContext {
  bool get isHindi => LangScope.of(this) == AppLanguage.hi;

  /// Bilingual string kept next to where it's used: `context.tr('Save', 'सेव करें')`.
  String tr(String en, String hi) => isHindi ? hi : en;

  /// Picks the Hindi name of a product/category when Hindi is on and one exists.
  String pick(String en, String? hi) => isHindi && hi != null && hi.trim().isNotEmpty ? hi : en;
}
