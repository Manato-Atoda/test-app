import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/identity_tabs.dart';
import '../widgets/like_button.dart';
import '../widgets/mindfulness.dart';
import '../widgets/rich_body.dart';
import 'user_profile_screen.dart';

/// 森の答え待ちの色（Galaxia のサイドバーと同じ）。
Color urgencyColor(Urgency u) => switch (u) {
  Urgency.calm => const Color(0xFFF43F5E),
  Urgency.soft => const Color(0xFFFDE047),
  Urgency.warm => const Color(0xFFF59E0B),
  Urgency.hot => const Color(0xFFEA580C),
};

/// わからんの森（トップ）。
class ForestScreen extends StatefulWidget {
  const ForestScreen({super.key});

  @override
  State<ForestScreen> createState() => ForestScreenState();
}

class ForestScreenState extends State<ForestScreen> {
  ForestHome? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final d = await AppScope.read(context).api.forest();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _ask() async {
    final q = await Navigator.of(context).push<Question>(
      MaterialPageRoute(builder: (_) => AskScreen(categories: _data?.categories ?? const []), fullscreenDialog: true),
    );
    if (q == null || !mounted) return;
    refresh();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => QuestionDetailScreen(questionId: q.id)));
  }

  void _openList({ForestCategory? category, String? filter, required String title}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => QuestionListScreen(title: title, categoryId: category?.id, filter: filter),
          ),
        )
        .then((_) => refresh());
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final p = context.m;
    Widget body;
    if (d == null) {
      body = _error != null
          ? MessageView(
              icon: Icons.cloud_off_outlined,
              message: _error is ApiException ? (_error as ApiException).message : '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: refresh,
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = Builder(
        builder: (context) => RefreshIndicator(
          onRefresh: refresh,
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: scrollPadding(context, const EdgeInsets.fromLTRB(12, 8, 12, 110)),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ForestHero(urgency: d.urgency, unanswered: d.unanswered.length),
                    if (d.unanswered.isNotEmpty) ...[
                      SectionLabel(
                        '答え待ちの質問',
                        trailing: TextButton(
                          onPressed: () => _openList(filter: 'unanswered', title: '答え待ちの質問'),
                          child: const Text('すべて'),
                        ),
                      ),
                      for (final q in d.unanswered) QuestionCard(question: q, onChanged: refresh),
                    ],
                    SectionLabel(
                      'カテゴリ',
                      trailing: TextButton(
                        onPressed: () => _openList(filter: 'mine', title: '自分の質問'),
                        child: const Text('自分の質問'),
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = c.maxWidth > 520 ? 3 : 2;
                        final w = (c.maxWidth - 10 * (cols - 1)) / cols;
                        return Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final cat in d.categories)
                              SizedBox(
                                width: w,
                                child: SoftCard(
                                  padding: const EdgeInsets.all(14),
                                  onTap: () => _openList(category: cat, title: cat.ref.label),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(cat.emoji ?? '🌳', style: const TextStyle(fontSize: 24)),
                                      const SizedBox(height: 6),
                                      Text(
                                        cat.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${cat.questionCount}件の質問',
                                        style: TextStyle(fontSize: 11.5, color: p.muted),
                                      ),
                                      if (cat.unansweredCount > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: TagPill(
                                            '未回答 ${cat.unansweredCount}',
                                            small: true,
                                            color: Colors.white,
                                            background: p.rose,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SectionLabel('最近の質問'),
                    if (d.recent.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'まだ質問はありません。\nわからないことを、気軽に森に投げかけてみましょう。',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, height: 1.6),
                        ),
                      ),
                    for (final q in d.recent) QuestionCard(question: q, onChanged: refresh),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: const GlassAppBar(title: Text('わからんの森 🌳')),
      floatingActionButton: GlassComposeButton(onPressed: _ask, label: '質問する', symbol: 'questionmark.bubble'),
      body: body,
    );
  }
}

class _ForestHero extends StatelessWidget {
  const _ForestHero({required this.urgency, required this.unanswered});

  final Urgency urgency;
  final int unanswered;

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final label = urgency.label;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x2610B981), Color(0x1A14B8A6), Color(0x1A6366F1)],
        ),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          const Text('🌳', style: TextStyle(fontSize: 34)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('わからんの森', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('わからないことは、森に投げかけよう。誰かがきっと答えてくれます。', style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.5)),
                if (label != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      NewDot(color: urgencyColor(urgency)),
                      const SizedBox(width: 6),
                      Text(
                        '$label（未回答 $unanswered件）',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 質問 1 件のカード。
class QuestionCard extends StatelessWidget {
  const QuestionCard({super.key, required this.question, this.onChanged});

  final Question question;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final p = context.m;
    final tag = identityTag(context, q.identity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        onTap: () => Navigator.of(context)
            .push(
              MaterialPageRoute<void>(
                builder: (_) => QuestionDetailScreen(questionId: q.id, initial: q),
              ),
            )
            .then((_) => onChanged?.call()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TagPill(q.category.label),
                const SizedBox(width: 6),
                if (q.unanswered)
                  TagPill('未回答', small: true, color: Colors.white, background: p.rose)
                else
                  TagPill(
                    '回答 ${q.answerCount}',
                    small: true,
                    color: p.success,
                    background: p.success.withValues(alpha: 0.12),
                  ),
                const Spacer(),
                Text(relativeTime(q.createdAt), style: TextStyle(fontSize: 11.5, color: p.muted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(q.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.4)),
            if (q.body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                q.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: p.muted, height: 1.5),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                AuthorAvatar(item: q, size: 22),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    q.shownName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                if (tag != null) ...[const SizedBox(width: 6), tag],
                const Spacer(),
                Icon(Icons.visibility_outlined, size: 14, color: p.muted),
                const SizedBox(width: 3),
                Text('${q.viewCount}', style: TextStyle(fontSize: 12, color: p.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 質問の一覧（カテゴリ別・答え待ち・自分の質問）。
class QuestionListScreen extends StatefulWidget {
  const QuestionListScreen({super.key, required this.title, this.categoryId, this.filter});

  final String title;
  final int? categoryId;
  final String? filter;

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  final List<Question> _items = [];
  int? _next;
  bool _loading = false;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && _next == null) return;
    setState(() => _loading = true);
    try {
      final page = await AppScope.read(context).api
          .questions(categoryId: widget.categoryId, filter: widget.filter, before: reset ? null : _next);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.questions);
        _next = page.nextBefore;
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!_loaded) {
      body = _error != null
          ? MessageView(
              icon: Icons.cloud_off_outlined,
              message: '読み込めませんでした。',
              actionLabel: '再読み込み',
              onAction: () => _load(reset: true),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      body = Builder(
        builder: (context) => RefreshIndicator(
          onRefresh: () => _load(reset: true),
          edgeOffset: MediaQuery.paddingOf(context).top,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: scrollPadding(context, const EdgeInsets.fromLTRB(12, 8, 12, 32)),
            itemCount: _items.length + 1,
            itemBuilder: (context, i) {
              if (i < _items.length) {
                return ContentWidth(
                  child: QuestionCard(question: _items[i], onChanged: () => _load(reset: true)),
                );
              }
              if (_items.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: MessageView(icon: Icons.park_outlined, message: '質問はまだありません'),
                );
              }
              if (_next != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _load());
                return const LoadingFooter();
              }
              return const SizedBox(height: 24);
            },
          ),
        ),
      );
    }
    return GlassScaffold(
      scrollUnderBars: true,
      appBar: GlassAppBar(title: Text(widget.title)),
      body: body,
    );
  }
}

/// 質問する。送信できたら [Question] を返す。
class AskScreen extends StatefulWidget {
  const AskScreen({super.key, required this.categories, this.initialCategoryId});

  final List<ForestCategory> categories;
  final int? initialCategoryId;

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late int? _categoryId = widget.initialCategoryId ?? (widget.categories.isEmpty ? null : widget.categories.first.id);
  Identity _identity = Identity.real;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _categoryId != null && _title.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final ok = await confirmMindfully(context, MindfulVariant.question);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final q = await AppScope.read(context).api
          .ask(categoryId: _categoryId!, title: _title.text.trim(), body: _body.text.trim(), identity: _identity);
      if (mounted) Navigator.of(context).pop(q);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('森に投げかける 🌳'),
        actions: [
          GlassBuilder(
            builder: (context, glass) => glass
                ? GlassButton(label: '質問する', style: GlassButtonStyle.prominent, onPressed: _canSubmit ? _submit : null)
                : Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GradientButton(
                      label: '質問する',
                      height: 38,
                      busy: _busy,
                      onPressed: _canSubmit ? _submit : null,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ContentWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'カテゴリ',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.muted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in widget.categories)
                        ChoiceChip(
                          label: Text(c.ref.label),
                          selected: _categoryId == c.id,
                          showCheckmark: false,
                          onSelected: _busy ? null : (_) => setState(() => _categoryId = c.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  IdentityTabs(value: _identity, enabled: !_busy, onChanged: (v) => setState(() => _identity = v)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _title,
                    enabled: !_busy,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: '質問のタイトル', hintText: '例) 経費精算の締め日はいつですか？'),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _body,
                    enabled: !_busy,
                    minLines: 5,
                    maxLines: 12,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: '詳しく（任意）',
                      hintText: '状況や、調べたこと・困っていることを書くと答えやすくなります',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 質問の詳細（回答・回答へのいいね・回答へのコメント）。
class QuestionDetailScreen extends StatefulWidget {
  const QuestionDetailScreen({super.key, required this.questionId, this.initial});

  final int questionId;
  final Question? initial;

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  Question? _question;
  List<Answer> _answers = const [];
  Object? _error;
  bool _loading = true;
  final _answer = TextEditingController();
  Identity _identity = Identity.real;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _question = widget.initial;
    _answer.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await AppScope.read(context).api.question(widget.questionId);
      if (!mounted) return;
      setState(() {
        _question = d.question;
        _answers = d.answers;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _answer.text.trim();
    if (text.isEmpty || _sending) return;
    final ok = await confirmMindfully(context, MindfulVariant.answer);
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      final a = await AppScope.read(context).api.answer(widget.questionId, body: text, identity: _identity);
      if (!mounted) return;
      _answer.clear();
      setState(() => _answers = [..._answers, a]);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _replace(Answer a) => setState(() => _answers = [for (final x in _answers) x.id == a.id ? a : x]);

  Future<void> _deleteQuestion() async {
    final ok = await confirmDialog(
      context,
      title: 'この質問を削除しますか？',
      message: '回答も表示されなくなります。',
      confirmLabel: '削除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).api.deleteQuestion(widget.questionId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _question;
    final p = context.m;
    final state = AppScope.of(context);
    final features = state.company?.features ?? const CompanyFeatures();

    Widget body;
    if (q == null) {
      body = _error != null
          ? MessageView(icon: Icons.error_outline, message: '読み込めませんでした。', actionLabel: '再読み込み', onAction: _load)
          : const Center(child: CircularProgressIndicator());
    } else {
      final tag = identityTag(context, q.identity);
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            ContentWidth(
              child: SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TagPill(q.category.label),
                        const Spacer(),
                        Icon(Icons.visibility_outlined, size: 14, color: p.muted),
                        const SizedBox(width: 3),
                        Text('${q.viewCount}', style: TextStyle(fontSize: 12, color: p.muted)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(q.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.4)),
                    if (q.body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      RichBody(q.body, style: const TextStyle(fontSize: 15, height: 1.6)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _AuthorLink(item: q, size: 28),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(q.shownName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                        if (tag != null) ...[const SizedBox(width: 6), tag],
                        const SizedBox(width: 6),
                        Text(relativeTime(q.createdAt), style: TextStyle(fontSize: 12, color: p.muted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            ContentWidth(child: SectionLabel('回答（${_answers.length}）')),
            if (_loading && _answers.isEmpty)
              const LoadingFooter()
            else if (_answers.isEmpty)
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('まだ回答はありません。知っていることがあれば、ぜひ答えてください。', style: TextStyle(color: p.muted)),
                ),
              ),
            for (final a in _answers)
              ContentWidth(
                child: _AnswerCard(
                  answer: a,
                  onChanged: _replace,
                  onDeleted: () => setState(() => _answers = _answers.where((x) => x.id != a.id).toList()),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('わからんの森'),
        actions: [
          if (q?.canDelete == true)
            GlassButton(symbol: 'trash', icon: Icons.delete_outline, tooltip: '質問を削除', onPressed: _deleteQuestion),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            if (q != null)
              Material(
                color: p.surfaceElevated,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  child: ContentWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (features.identityDepartment || features.identityAnonymous) ...[
                            IdentityTabs(value: _identity, onChanged: (v) => setState(() => _identity = v)),
                            const SizedBox(height: 6),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _answer,
                                  enabled: !_sending,
                                  minLines: 1,
                                  maxLines: 6,
                                  maxLength: 4000,
                                  decoration: const InputDecoration(hintText: '回答を書く', counterText: '', isDense: true),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton.filled(
                                tooltip: '回答を送る',
                                style: IconButton.styleFrom(backgroundColor: p.accent),
                                onPressed: _answer.text.trim().isEmpty || _sending ? null : _send,
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuthorLink extends StatelessWidget {
  const _AuthorLink({required this.item, this.size = 32});

  final Authored item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = item.author;
    return GestureDetector(
      onTap: item.identity == Identity.real && a != null
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UserProfileScreen(userId: a.id)))
          : null,
      child: AuthorAvatar(item: item, size: size),
    );
  }
}

class _AnswerCard extends StatefulWidget {
  const _AnswerCard({required this.answer, required this.onChanged, required this.onDeleted});

  final Answer answer;
  final ValueChanged<Answer> onChanged;
  final VoidCallback onDeleted;

  @override
  State<_AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends State<_AnswerCard> {
  final _comment = TextEditingController();
  bool _showComposer = false;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Answer get a => widget.answer;

  Future<void> _like() async {
    try {
      widget.onChanged(await AppScope.read(context).api.setAnswerLike(a.id, !a.likedByMe));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'この回答を削除しますか？', message: '', confirmLabel: '削除', destructive: true);
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).api.deleteAnswer(a.id);
      widget.onDeleted();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final c = await AppScope.read(context).api.commentOnAnswer(a.id, body: text, identity: Identity.real);
      _comment.clear();
      widget.onChanged(a.withComments([...a.comments, c]));
      if (mounted) setState(() => _showComposer = false);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteComment(AnswerComment c) async {
    try {
      await AppScope.read(context).api.deleteAnswerComment(c.id);
      widget.onChanged(a.withComments(a.comments.where((x) => x.id != c.id).toList()));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.m;
    final tag = identityTag(context, a.identity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _AuthorLink(item: a, size: 30),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(a.shownName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                if (tag != null) ...[const SizedBox(width: 6), tag],
                const SizedBox(width: 6),
                Text(relativeTime(a.createdAt), style: TextStyle(fontSize: 11.5, color: p.muted)),
                const Spacer(),
                if (a.canDelete)
                  IconButton(
                    tooltip: '回答を削除',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline, size: 18, color: p.muted),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            RichBody(a.body, style: const TextStyle(fontSize: 14.5, height: 1.6)),
            Row(
              children: [
                LikeButton(liked: a.likedByMe, count: a.likeCount, onToggle: _like, compact: true),
                TextButton.icon(
                  onPressed: () => setState(() => _showComposer = !_showComposer),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: Text(a.comments.isEmpty ? 'コメント' : 'コメント ${a.comments.length}'),
                ),
              ],
            ),
            for (final c in a.comments)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthorAvatar(item: c, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${c.shownName}  ',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: c.body),
                            TextSpan(
                              text: '  ${relativeTime(c.createdAt)}',
                              style: TextStyle(color: p.muted, fontSize: 11),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ),
                    if (c.canDelete)
                      InkWell(
                        onTap: () => _deleteComment(c),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, size: 14, color: p.muted),
                        ),
                      ),
                  ],
                ),
              ),
            if (_showComposer)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comment,
                        autofocus: true,
                        maxLength: 2000,
                        decoration: const InputDecoration(hintText: '回答へのコメント（実名）', isDense: true, counterText: ''),
                        onSubmitted: (_) => _sendComment(),
                      ),
                    ),
                    IconButton(
                      tooltip: '送信',
                      onPressed: _busy ? null : _sendComment,
                      icon: Icon(Icons.send_rounded, color: p.accent),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
