import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/connection/connection.dart';
import 'package:myptt/core/encoding/big5_codec.dart';
import 'package:myptt/core/login/credentials.dart';
import 'package:myptt/ui/login_page.dart';
import 'package:myptt/ui/terminal_page.dart';

import '../support/fake_connection.dart';
import '../support/fake_credential_store.dart';

void main() {
  final codec = Big5Codec(
    File('assets/uao/b2u.bin').readAsBytesSync(),
    File('assets/uao/u2b.bin').readAsBytesSync(),
  );

  late FakeCredentialStore store;
  late List<FakeConnection> connections;

  Future<void> pumpLogin(WidgetTester tester, {Credentials? saved}) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store = FakeCredentialStore(saved);
    connections = [];
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        codec: codec,
        store: store,
        connectionFactory: () {
          final c = FakeConnection();
          connections.add(c);
          return c;
        },
      ),
    ));
    await tester.pump();
  }

  Future<void> disposeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);
  String sentText() => String.fromCharCodes(connections.single.sent);
  void show(String text) => connections.single.emit(codec.encode(text).bytes);

  testWidgets('logging in connects and types the credentials', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();

    expect(find.byType(TerminalPage), findsOneWidget);
    expect(connections.single.status, ConnectionStatus.connected);
    show('請輸入代號，或以 guest 參觀，或以 new 註冊: ');
    expect(sentText(), 'alice\r');
    show('\r\n請輸入您的密碼: ');
    expect(sentText(), 'alice\rs3cret\r');
    await disposeAll(tester);
  });

  testWidgets('credentials are saved only when remember is checked', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(store.clears, 1);
    await disposeAll(tester);

    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'bob');
    await tester.enterText(field('密碼'), 'pw');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(store.saved?.userId, 'bob');
    expect(store.saved?.password, 'pw');
    await disposeAll(tester);
  });

  testWidgets('saved credentials are filled in with remember checked', (tester) async {
    await pumpLogin(tester, saved: const Credentials('alice', 's3cret'));
    expect(find.text('alice'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(tester.widget<TextField>(field('密碼')).obscureText, isTrue);
    expect(tester.widget<TextField>(field('密碼')).controller?.text, 's3cret');
    await disposeAll(tester);
  });

  testWidgets('invalid input shows a message and does not connect', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.text('登入'));
    await tester.pump();
    expect(find.text('請輸入帳號與密碼'), findsOneWidget);

    await tester.enterText(field('帳號'), '愛麗絲');
    await tester.enterText(field('密碼'), 'pw');
    await tester.tap(find.text('登入'));
    await tester.pump();
    expect(find.text('帳號只能是 1 到 12 個英文字母或數字'), findsOneWidget);

    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), '');
    await tester.tap(find.text('登入'));
    await tester.pump();
    expect(find.text('請輸入帳號與密碼'), findsOneWidget);

    expect(connections, isEmpty);
    expect(find.byType(TerminalPage), findsNothing);
    await disposeAll(tester);
  });

  testWidgets('surrounding spaces in the id are ignored', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), '  alice ');
    await tester.enterText(field('密碼'), ' pw ');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    show('請輸入代號: ');
    expect(sentText(), 'alice\r');
    show('\r\n請輸入您的密碼: ');
    expect(sentText(), 'alice\r pw \r');
    await disposeAll(tester);
  });

  testWidgets('connecting without auto-login types nothing and keeps the keychain',
      (tester) async {
    await pumpLogin(tester, saved: const Credentials('alice', 's3cret'));
    await tester.tap(find.text('不自動登入，直接連線'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalPage), findsOneWidget);
    show('請輸入代號: ');
    expect(connections.single.sent, isEmpty);
    expect(store.saved?.userId, 'alice');
    expect(store.clears, 0);
    await disposeAll(tester);
  });

  testWidgets('keychain failures do not block logging in', (tester) async {
    await pumpLogin(tester);
    store.saveError = StateError('keychain locked');
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(find.byType(TerminalPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await disposeAll(tester);

    store = FakeCredentialStore()..loadError = StateError('keychain locked');
    connections = [];
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(codec: codec, store: store),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('登入'), findsOneWidget);
    await disposeAll(tester);
  });

  testWidgets('going back from the terminal closes the connection and each login gets a new one',
      (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 's3cret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.byType(TerminalPage))).pop();
    await tester.pumpAndSettle();
    expect(connections.single.status, ConnectionStatus.disconnected);
    expect(find.text('登入'), findsOneWidget);

    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    expect(connections.length, 2);
    expect(connections.last.status, ConnectionStatus.connected);
    await disposeAll(tester);
  });

  testWidgets('the password never appears in visible text', (tester) async {
    await pumpLogin(tester);
    await tester.enterText(field('帳號'), 'alice');
    await tester.enterText(field('密碼'), 'Sup3rSecret');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();
    connections.single.drop();
    await tester.pump();
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.data ?? '', isNot(contains('Sup3rSecret')));
    }
    await disposeAll(tester);
  });
}
