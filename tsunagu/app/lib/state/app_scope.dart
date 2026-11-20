import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// 画面から [AppState] を取り出すための入れ物。
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  /// 変更を購読する（ログイン状態・未読数などで再描画したい画面用）。
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 購読せずに取り出す（ボタンの処理など）。
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
