import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(TsunaguApp(state: state));
  state.init();
}
