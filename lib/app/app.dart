import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/healthcare_service.dart';
import '../services/messaging_service.dart';
import '../services/notification_service.dart';
import '../services/pet_service.dart';
import '../services/store_service.dart';
import '../utils/constants.dart';
import 'routes.dart';
import 'theme.dart';

/// Application root. Owns the Provider scope, theme mode and routing.
class PetHubApp extends StatefulWidget {
  const PetHubApp({super.key});

  @override
  State<PetHubApp> createState() => _PetHubAppState();
}

class _PetHubAppState extends State<PetHubApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _restoreThemeMode();
  }

  /// Light/dark choice is persisted so the app opens in the mode the user
  /// last picked instead of always falling back to the system setting.
  Future<void> _restoreThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(AppConstants.keyThemeMode);
      final mode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.light,
      };
      if (!mounted) return;
      setState(() => _themeMode = mode);
    } catch (_) {
      // Keep the system default if storage is unavailable.
    }
  }

  Future<void> _toggleTheme(bool dark) async {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyThemeMode, dark ? 'dark' : 'light');
    } catch (_) {
      /* no-op */
    }
  }
  /// Exposed so the profile screen can flip dark mode from settings.
  static _PetHubAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_PetHubAppState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => PetService()),
        ChangeNotifierProvider(create: (_) => StoreService()),
        ChangeNotifierProvider(create: (_) => HealthcareService()),
        // Declared before [MessagingService] so the latter can raise an alert
        // for every buyer or seller message that arrives.
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(
          create: (context) => MessagingService(
            onMessageReceived: (thread, message) =>
                context.read<NotificationService>().messageReceived(
                  threadId: thread.id,
                  senderName: thread.participantName,
                  preview: message.text,
                ),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'petbloom',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeMode,
        initialRoute: AppRoutes.splash,
        onGenerateRoute: (settings) {
          final builder = AppRoutes.all[settings.name];
          if (builder == null) return null;
          return MaterialPageRoute<void>(settings: settings, builder: builder);
        },
        builder: (context, child) {
          // Clamp text scaling so the dense cards stay readable.
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.25,
              ),
            ),
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: Theme.of(context).brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}

/// Allows any descendant to switch between light and dark mode.
class ThemeSwitcher {
  ThemeSwitcher._();

  static void setDarkMode(BuildContext context, bool isDark) {
    _PetHubAppState.of(context)?._toggleTheme(isDark);
  }
}
