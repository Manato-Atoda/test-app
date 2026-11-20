import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import 'common.dart';

/// 入力中の「@…」に合わせて社員の候補を出し、選ぶと「@社員コード 」を入れる。
class MentionSuggestions extends StatefulWidget {
  const MentionSuggestions({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  static final _pattern = RegExp(r'(?:^|[\s　])@([A-Za-z0-9_.\-]{0,32}|[^\s　@]{0,16})$');

  Timer? _debounce;
  String? _query;
  List<UserSummary> _users = const [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  String? _currentQuery() {
    final value = widget.controller.value;
    final cursor = value.selection.baseOffset;
    if (cursor < 0 || cursor > value.text.length) return null;
    final m = _pattern.firstMatch(value.text.substring(0, cursor));
    return m?.group(1);
  }

  void _onChanged() {
    final q = _currentQuery();
    if (q == _query) return;
    _query = q;
    _debounce?.cancel();
    if (q == null) {
      if (_users.isNotEmpty) setState(() => _users = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      try {
        final list = await AppScope.read(context).api.directory(q: q.isEmpty ? null : q);
        if (mounted && _query == q) setState(() => _users = list.take(6).toList());
      } catch (_) {
        // 候補が出ないだけ。
      }
    });
  }

  void _insert(UserSummary u) {
    final value = widget.controller.value;
    final cursor = value.selection.baseOffset;
    final before = value.text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at < 0) return;
    final insert = '@${u.employeeCode} ';
    final text = value.text.replaceRange(at, cursor, insert);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: at + insert.length),
    );
    setState(() {
      _users = const [];
      _query = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_users.isEmpty) return const SizedBox.shrink();
    final p = context.m;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: p.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final u in _users)
            ListTile(
              dense: true,
              leading: UserAvatar(user: u, size: 30),
              title: Text(u.displayName),
              subtitle: Text('@${u.employeeCode}${u.affiliation.isEmpty ? '' : ' · ${u.affiliation}'}'),
              onTap: () => _insert(u),
            ),
        ],
      ),
    );
  }
}
