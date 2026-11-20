import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import '../widgets/post_card.dart';

/// 投稿の検索（自分が見られるチャンネルの投稿のみ）。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Post>? _results;
  bool _loading = false;
  String _lastQuery = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _lastQuery = q;
    });
    try {
      final posts = await AppScope.read(context).api.search(q);
      if (mounted) setState(() => _results = posts);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _replace(Post p) {
    final list = _results;
    if (list == null) return;
    setState(() => _results = [for (final x in list) x.id == p.id ? p : x]);
  }

  void _remove(int id) {
    final list = _results;
    if (list == null) return;
    setState(() => _results = list.where((x) => x.id != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            hintText: '投稿を検索',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(tooltip: '検索', onPressed: _search, icon: const Icon(Icons.search)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : results == null
          ? const MessageView(icon: Icons.search, message: 'キーワードを入力して検索します。')
          : results.isEmpty
          ? MessageView(icon: Icons.search_off, message: '「$_lastQuery」に一致する投稿はありません。')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: results.length,
              itemBuilder: (context, i) => ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PostCard(
                    key: ValueKey(results[i].id),
                    post: results[i],
                    onChanged: _replace,
                    onDeleted: _remove,
                  ),
                ),
              ),
            ),
    );
  }
}
