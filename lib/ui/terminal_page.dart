import 'package:flutter/material.dart';

import '../core/connection/connection.dart';
import 'input_strip.dart';
import 'key_bar.dart';
import 'session_controller.dart';
import 'terminal_surface.dart';

/// The terminal screen: the surface, the input controls, and what to show
/// while connecting, disconnected, or browsing offline.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.controller, this.openUrl});

  /// Owned by this page: connected on open, disposed on close.
  final SessionController controller;

  /// Opens a link in the system browser. Null disables link taps.
  final Future<bool> Function(String url)? openUrl;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  final _inputFocus = FocusNode();
  final _ctrlLatch = ValueNotifier<bool>(false);

  SessionController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onControllerChanged);
    _controller.connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _inputFocus.dispose();
    _ctrlLatch.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.onResumed();
  }

  void _toggleKeyboard() {
    if (!_controller.inputEnabled) return;
    if (_inputFocus.hasFocus) {
      _inputFocus.unfocus();
    } else {
      _inputFocus.requestFocus();
    }
  }

  void _showCopied(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('已複製 ${text.runes.length} 個字'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final openUrl = widget.openUrl;
    final navigator = Navigator.maybeOf(context);
    final VoidCallback? onLeave = navigator != null && navigator.canPop()
        ? navigator.pop
        : null;
    // Swiping right is the BBS "back" key, so the system back gesture must
    // not close this page. Leaving is offered once the connection is down.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              if (c.connecting || c.status == ConnectionStatus.connecting)
                const _Banner(label: '連線中…')
              else if (c.offline)
                _Banner(
                  label: '已離線',
                  actionLabel: '重新連線',
                  onAction: c.connect,
                  onLeave: onLeave,
                ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    TerminalSurface(
                      session: c.session,
                      inputEnabled: c.inputEnabled,
                      onTapBackground: _toggleKeyboard,
                      onOpenUrl: openUrl == null ? null : (url) => openUrl(url),
                      onCopied: _showCopied,
                    ),
                    if (c.showDisconnectedOverlay)
                      _DisconnectedOverlay(
                        error: c.error,
                        canBrowse: c.everConnected,
                        onReconnect: c.connect,
                        onBrowse: c.browseOffline,
                        onLeave: onLeave,
                      ),
                  ],
                ),
              ),
              if (c.inputEnabled) ...[
                InputStrip(
                  session: c.session,
                  focusNode: _inputFocus,
                  ctrlLatch: _ctrlLatch,
                ),
                KeyBar(session: c.session, ctrlLatch: _ctrlLatch),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.label,
    this.actionLabel,
    this.onAction,
    this.onLeave,
  });

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Returns to the previous page; null when there is none.
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          if (onLeave != null)
            TextButton(onPressed: onLeave, child: const Text('返回登入頁')),
        ],
      ),
    );
  }
}

class _DisconnectedOverlay extends StatelessWidget {
  const _DisconnectedOverlay({
    required this.error,
    required this.canBrowse,
    required this.onReconnect,
    required this.onBrowse,
    this.onLeave,
  });

  /// Why connecting failed, or null for a connection that simply dropped.
  final String? error;

  /// Whether there is a last screen worth looking at.
  final bool canBrowse;
  final VoidCallback onReconnect;
  final VoidCallback onBrowse;

  /// Returns to the previous page; null when there is none.
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return ColoredBox(
      color: const Color(0xB3000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error == null ? '已斷線' : '連線失敗',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center, maxLines: 4),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: onReconnect, child: const Text('重新連線')),
              if (canBrowse)
                TextButton(onPressed: onBrowse, child: const Text('繼續瀏覽')),
              if (onLeave != null)
                TextButton(onPressed: onLeave, child: const Text('返回登入頁')),
            ],
          ),
        ),
      ),
    );
  }
}
