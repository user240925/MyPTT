import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/connection/connection.dart';
import 'core/connection/ws_connection.dart';
import 'core/encoding/big5_codec.dart';
import 'core/session.dart';
import 'ui/terminal_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final b2u = await rootBundle.load('assets/uao/b2u.bin');
  final u2b = await rootBundle.load('assets/uao/u2b.bin');
  final codec = Big5Codec(
    b2u.buffer.asUint8List(b2u.offsetInBytes, b2u.lengthInBytes),
    u2b.buffer.asUint8List(u2b.offsetInBytes, u2b.lengthInBytes),
  );
  runApp(MyPttApp(session: TerminalSession(WsConnection(), codec)));
}

class MyPttApp extends StatefulWidget {
  const MyPttApp({super.key, required this.session});

  final TerminalSession session;

  @override
  State<MyPttApp> createState() => _MyPttAppState();
}

class _MyPttAppState extends State<MyPttApp> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _error = null);
    try {
      await widget.session.connect();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyPTT',
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              StreamBuilder<void>(
                stream: widget.session.updates,
                builder: (context, _) => _StatusBar(
                  status: widget.session.status,
                  error: _error,
                  onReconnect: _connect,
                ),
              ),
              Expanded(child: TerminalView(session: widget.session)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.status,
    required this.error,
    required this.onReconnect,
  });

  final ConnectionStatus status;
  final String? error;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      ConnectionStatus.connected => '已連線',
      ConnectionStatus.connecting => '連線中…',
      ConnectionStatus.disconnected => error == null ? '已斷線' : '連線失敗：$error',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (status == ConnectionStatus.disconnected)
            TextButton(onPressed: onReconnect, child: const Text('重新連線')),
        ],
      ),
    );
  }
}
