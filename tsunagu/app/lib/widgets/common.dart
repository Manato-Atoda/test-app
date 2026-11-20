import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme.dart';
import 'auth_image.dart';
import 'brand.dart';

/// 広い画面では中央寄せ・最大幅で表示する。
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // 中身が小さくても、最大幅（狭い画面では画面幅）いっぱいに広げる
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 40});

  final UserSummary user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = avatarPalette[user.avatarColor.abs() % avatarPalette.length];
    final name = user.displayName.trim();
    final initial = name.isEmpty ? '?' : String.fromCharCode(name.runes.first);
    final url = user.avatarUrl;
    return Semantics(
      label: user.displayName,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: url != null
              ? AuthImage(url, width: size, height: size)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: user.isActive
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, Color.lerp(color, Colors.black, 0.18)!],
                          )
                        : null,
                    color: user.isActive ? null : Colors.grey,
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.42),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// 投稿者のアバター。実名ならその人、部署名・匿名なら専用の絵。
class AuthorAvatar extends StatelessWidget {
  const AuthorAvatar({super.key, required this.item, this.size = 40});

  final Authored item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final author = item.author;
    if (item.identity == Identity.real && author != null) return UserAvatar(user: author, size: size);
    final p = context.m;
    final department = item.identity == Identity.department;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: department ? p.accentSoft : p.borderSoft,
        border: Border.all(color: p.border),
      ),
      child: Icon(
        department ? Icons.apartment_rounded : Icons.theater_comedy_outlined,
        size: size * 0.5,
        color: department ? p.accent : p.muted,
      ),
    );
  }
}

/// 名前の横に付ける「部署」「匿名」のラベル。実名なら null。
Widget? identityTag(BuildContext context, Identity identity) {
  final p = context.m;
  switch (identity) {
    case Identity.real:
      return null;
    case Identity.department:
      return TagPill('部署', small: true);
    case Identity.anonymous:
      return TagPill('匿名', small: true, color: p.muted, background: p.borderSoft);
  }
}

/// 氏名に「（停止中）」などを付ける。
String displayNameWithStatus(UserSummary user) {
  switch (user.status) {
    case 'suspended':
      return '${user.displayName}（利用停止）';
    case 'retired':
      return '${user.displayName}（退職）';
    default:
      return user.displayName;
  }
}

class MessageView extends StatelessWidget {
  const MessageView({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// エラーを画面下に表示する（セッション切れはログイン画面に戻るので出さない）。
void showError(BuildContext context, Object error) {
  if (error is ApiException && (error.isSessionError || error.isPasswordChangeRequired)) return;
  final message = error is ApiException ? error.message : 'エラーが発生しました。';
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// 1 項目だけ入力するダイアログ。キャンセルで null。
Future<String?> textInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? hint,
  String confirmLabel = '保存',
  int maxLength = 4000,
  int maxLines = 6,
  bool allowEmpty = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      hint: hint,
      confirmLabel: confirmLabel,
      maxLength: maxLength,
      maxLines: maxLines,
      allowEmpty: allowEmpty,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialValue,
    required this.hint,
    required this.confirmLabel,
    required this.maxLength,
    required this.maxLines,
    required this.allowEmpty,
  });

  final String title;
  final String initialValue;
  final String? hint;
  final String confirmLabel;
  final int maxLength;
  final int maxLines;
  final bool allowEmpty;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 1,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          decoration: InputDecoration(hintText: widget.hint),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
        FilledButton(
          onPressed: widget.allowEmpty || _controller.text.trim().isNotEmpty
              ? () => Navigator.pop(context, _controller.text.trim())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 一覧の末尾に出す読み込み中表示。
class LoadingFooter extends StatelessWidget {
  const LoadingFooter({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: CircularProgressIndicator()),
  );
}
