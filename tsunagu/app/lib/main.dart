import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'state/app_state.dart';
import 'widgets/glass.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS 26 以降ならリキッドグラスを使う（先に調べておくと、起動直後から見た目がそろう）
  await GlassSupport.init();
  final state = AppState();
  runApp(TsunaguApp(state: state));
  state.init();
}
