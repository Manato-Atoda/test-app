import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../theme.dart';
import 'common.dart';

/// アプリ表示中に届いた通知を、画面の上からバナーで出す（数秒で消える・タップで開く）。
class InAppBanner extends StatefulWidget {
  const InAppBanner({super.key, required this.child, required this.onOpen});

  final Widget child;
  final void Function(AppNotification notification) onOpen;

  @override
  State<InAppBanner> createState() => _InAppBannerState();
}

class _InAppBannerState extends State<InAppBanner> {
  AppNotification? _shown;
  Timer? _timer;
  ValueNotifier<AppNotification?>? _source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = AppScope.read(context).banner;
    if (!identical(source, _source)) {
      _source?.removeListener(_onBanner);
      _source = source..addListener(_onBanner);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _source?.removeListener(_onBanner);
    super.dispose();
  }

  void _onBanner() {
    final n = _source?.value;
    if (n == null) return;
    _timer?.cancel();
    setState(() => _shown = n);
    _timer = Timer(const Duration(seconds: 5), _hide);
  }

  void _hide() {
    if (!mounted) return;
    setState(() => _shown = null);
    _source?.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final n = _shown;
    final p = context.m;
    return Stack(
      children: [
        widget.child,
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          left: 12,
          right: 12,
          top: n == null ? -160 : MediaQuery.paddingOf(context).top + 8,
          child: n == null
              ? const SizedBox.shrink()
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Material(
                      color: p.surfaceElevated,
                      elevation: 8,
                      shadowColor: const Color(0x330F172A),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          _hide();
                          widget.onOpen(n);
                        },
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                          child: Row(
                            children: [
                              if (n.actor != null)
                                UserAvatar(user: n.actor!, size: 36)
                              else
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: p.accentSoft,
                                  child: Icon(Icons.notifications_rounded, color: p.accent, size: 20),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      n.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                    ),
                                    if (n.excerpt.isNotEmpty)
                                      Text(
                                        n.excerpt,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12.5, color: p.muted),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: '閉じる',
                                visualDensity: VisualDensity.compact,
                                onPressed: _hide,
                                icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
