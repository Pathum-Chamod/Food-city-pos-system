import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { english, sinhala }

extension AppLanguageX on AppLanguage {
  String get storageValue => this == AppLanguage.sinhala ? 'si' : 'en';

  String get label => this == AppLanguage.sinhala ? 'සිංහල' : 'English';

  String get shortLabel => this == AppLanguage.sinhala ? 'සිං' : 'EN';
}

class LanguageProvider extends ChangeNotifier {
  static const _storageKey = 'fc_app_language';

  AppLanguage _language = AppLanguage.english;

  AppLanguage get language => _language;
  bool get isSinhala => _language == AppLanguage.sinhala;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_storageKey);
    _language = value == AppLanguage.sinhala.storageValue
        ? AppLanguage.sinhala
        : AppLanguage.english;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, language.storageValue);
  }

  Future<void> toggle() async {
    await setLanguage(isSinhala ? AppLanguage.english : AppLanguage.sinhala);
  }
}
