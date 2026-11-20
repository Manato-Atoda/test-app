import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'screens/guidelines_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/password_change_screen.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'theme.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class TsunaguApp extends StatelessWidget {
  const TsunaguApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        navigatorKey: rootNavigatorKey,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('ja', 'JP'),
        supportedLocales: const [Locale('ja', 'JP')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const _RootGate(),
      ),
    );
  }
}

/// ログイン状態に応じて最初の画面を切り替える。
class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  AppPhase? _lastPhase;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (_lastPhase != null && _lastPhase != state.phase) {
      // 画面の段階が変わったら、上に積まれた画面（投稿詳細など）を閉じる。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      });
    }
    _lastPhase = state.phase;

    final Widget child = switch (state.phase) {
      AppPhase.starting => const _Splash(),
      AppPhase.loggedOut => const LoginScreen(),
      AppPhase.passwordChange => const PasswordChangeScreen.required(),
      AppPhase.guidelines => const GuidelinesScreen.accept(),
      AppPhase.ready => const HomeShell(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(key: ValueKey(state.phase), child: child),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
