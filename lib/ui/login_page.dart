import 'package:flutter/material.dart';

import '../core/connection/connection.dart';
import '../core/connection/ws_connection.dart';
import '../core/encoding/big5_codec.dart';
import '../core/login/credentials.dart';
import '../core/session.dart';
import 'session_controller.dart';
import 'terminal_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.codec,
    required this.store,
    this.connectionFactory = defaultConnection,
    this.openUrl,
  });

  final Big5Codec codec;
  final CredentialStore store;

  /// Creates the connection for each new session.
  final Connection Function() connectionFactory;
  final Future<bool> Function(String url)? openUrl;

  static Connection defaultConnection() => WsConnection();

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userId = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _userId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    Credentials? saved;
    try {
      saved = await widget.store.load();
    } catch (_) {
      // An unreadable keychain is the same as an empty one.
    }
    final credentials = saved;
    if (!mounted || credentials == null) return;
    setState(() {
      _userId.text = credentials.userId;
      _password.text = credentials.password;
      _remember = true;
    });
  }

  Future<void> _login() async {
    final userId = _userId.text.trim();
    final password = _password.text;
    if (userId.isEmpty || password.isEmpty) {
      setState(() => _message = '請輸入帳號與密碼');
      return;
    }
    if (!isValidUserId(userId)) {
      setState(() => _message = '帳號只能是 1 到 12 個英文字母或數字');
      return;
    }
    setState(() => _message = null);

    final credentials = Credentials(userId, password);
    try {
      if (_remember) {
        await widget.store.save(credentials);
      } else {
        await widget.store.clear();
      }
    } catch (_) {
      // Failing to remember must not stop the user from logging in.
    }
    if (!mounted) return;
    _openTerminal(credentials);
  }

  void _openTerminal(Credentials? credentials) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TerminalPage(
        controller: SessionController(
          TerminalSession(widget.connectionFactory(), widget.codec),
          credentials: credentials,
        ),
        openUrl: widget.openUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'MyPTT',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _userId,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: '帳號'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(labelText: '密碼'),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (v) => setState(() => _remember = v ?? false),
                      ),
                      const Expanded(child: Text('記住帳號密碼')),
                    ],
                  ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        message,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  FilledButton(onPressed: _login, child: const Text('登入')),
                  TextButton(
                    onPressed: () => _openTerminal(null),
                    child: const Text('不自動登入，直接連線'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
