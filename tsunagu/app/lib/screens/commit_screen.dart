import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/feed_view.dart';
import '../widgets/glass.dart';
import 'compose_screen.dart';

/// COMMIT（「何を、いつまでに、どこまでやるか」を自分の言葉で言い切る宣言）。
class CommitScreen extends StatefulWidget {
  const CommitScreen({super.key});

  @override
  State<CommitScreen> createState() => CommitScreenState();
}

class CommitScreenState extends State<CommitScreen> {
  static const _periods = <(String, String)>[('today', '今日'), ('week', '今週'), ('month', '今月'), ('all', 'すべて')];

  String _period = 'all';
  UserSummary? _member;
  late FeedController _feed = _make();

  FeedController _make() {
    final api = AppScope.read(context).api;
    final period = _period;
    final userId = _member?.id;
    return FeedController(
      fetch: (before) => api.commits(userId: userId, period: period, before: before),
      accepts: (p) => (p.isCommit || p.quoteOf?.isCommit == true) && (userId == null || p.author?.id == userId),
    );
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  /// 最新に読み直す（タブをもう一度押したとき）。
  void refresh() => _feed.refresh();

  void _setFilter({String? period, UserSummary? member, bool clearMember = false}) {
    final old = _feed;
    setState(() {
      if (period != null) _period = period;
      if (clearMember) _member = null;
      if (member != null) _member = member;
      _feed = _make();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> _compose() async {
    final post = await Navigator.of(context)
        .push<Post>(MaterialPageRoute(builder: (_) => const ComposeScreen.commit(), fullscreenDialog: true));
    if (post != null) _feed.insertNew(post);
  }

  Future<void> _pickMember() async {
    final picked = await showModalBottomSheet<UserSummary?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _MemberPicker(),
    );
    if (picked == null) return;
    if (picked.id == -1) {
      _setFilter(clearMember: true);
    } else {
      _setFilter(member: picked);
    }
  }

  void _explain() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('COMMIT って何？'),
        content: const SingleChildScrollView(
          child: Text(
            '「自分は、いつまでに、どこまでやるのか」を自分の言葉で言い切る場所です。\n\n'
            '・金曜日までに採用サイトの初稿を出します\n'
            '・今日17時までに提案資料を完成させます\n'
            '・今週はアポ3件取ります\n\n'
            '大きな目標じゃなくて大丈夫です。営業でも、制作でも、学生の仕事でも、その人なりの責任があるはずです。'
            '何をするのか、いつまでにやるのか、どこまでやるのか。それを頭の中だけで決めるのではなく、自分の言葉として外に出す。そこに意味があります。\n\n'
            '自分で言い切ると、その言葉に責任が生まれる。だから、早く動く。考える。人に頼む。必要なら相談する。'
            'そうやって行動が変わっていきます。',
            style: TextStyle(height: 1.6),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final me = AppScope.of(context).me;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          padding: const EdgeInsets.all(16),
          onTap: _compose,
          child: Row(
            children: [
              if (me != null) UserAvatar(user: me, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '何を、いつまでに、どこまでやる？\n例) 金曜までに採用サイトの初稿を出します',
                  style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.5),
                ),
              ),
              Icon(Icons.flag_rounded, color: p.rose),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ActionChip(
              avatar: Icon(Icons.person_search_outlined, size: 18, color: p.accent),
              label: Text(_member == null ? '全員' : _member!.displayName),
              onPressed: _pickMember,
            ),
            for (final (value, label) in _periods)
              ChoiceChip(
                label: Text(label),
                selected: _period == value,
                showCheckmark: false,
                onSelected: (_) => _setFilter(period: value),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: GlassAppBar(
        title: const Text('COMMIT'),
        actions: [
          GlassButton(
            symbol: 'questionmark.circle',
            icon: Icons.help_outline,
            tooltip: 'COMMIT って何？',
            onPressed: _explain,
          ),
        ],
      ),
      floatingActionButton: GlassComposeButton(onPressed: _compose, label: 'COMMIT', symbol: 'flag'),
      body: FeedView(
        key: ValueKey('$_period-${_member?.id}'),
        controller: _feed,
        header: header,
        emptyMessage: 'まだ COMMIT はありません',
        emptyIcon: Icons.flag_outlined,
      ),
    );
  }
}

/// メンバーを選ぶ（「全員」は id = -1 の印で返す）。
class _MemberPicker extends StatefulWidget {
  const _MemberPicker();

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  List<UserSummary>? _users;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).api.directory(q: _q.isEmpty ? null : _q);
      if (mounted) setState(() => _users = list);
    } catch (_) {
      if (mounted) setState(() => _users = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '氏名・部署で探す', isDense: true),
                onChanged: (v) {
                  _q = v.trim();
                  _load();
                },
              ),
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
              title: const Text('全員'),
              onTap: () => Navigator.pop(
                context,
                const UserSummary(
                  id: -1,
                  displayName: '全員',
                  employeeCode: '',
                  department: '',
                  title: '',
                  avatarColor: 0,
                  role: 'member',
                  status: 'active',
                ),
              ),
            ),
            Expanded(
              child: users == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, i) => ListTile(
                        leading: UserAvatar(user: users[i], size: 36),
                        title: Text(users[i].displayName),
                        subtitle: Text(users[i].affiliation),
                        onTap: () => Navigator.pop(context, users[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
