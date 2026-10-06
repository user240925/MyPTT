import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/encoding/big5_codec.dart';
import 'platform/link_opener.dart';
import 'platform/secure_credential_store.dart';
import 'ui/login_page.dart';

Future<Big5Codec> loadCodec() async {
  final b2u = await rootBundle.load('assets/uao/b2u.bin');
  final u2b = await rootBundle.load('assets/uao/u2b.bin');
  return Big5Codec(
    b2u.buffer.asUint8List(b2u.offsetInBytes, b2u.lengthInBytes),
    u2b.buffer.asUint8List(u2b.offsetInBytes, u2b.lengthInBytes),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final codec = await loadCodec();
  runApp(MaterialApp(
    title: 'MyPTT',
    theme: ThemeData.dark(),
    home: LoginPage(
      codec: codec,
      store: const SecureCredentialStore(),
      openUrl: openExternalUrl,
    ),
  ));
}
