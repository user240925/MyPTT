import 'package:flutter_test/flutter_test.dart';
import 'package:myptt/core/login/auto_login.dart';
import 'package:myptt/core/login/credentials.dart';

const idPrompt = '請輸入代號，或以 guest 參觀，或以 new 註冊:';
const passwordPrompt = '請輸入您的密碼:';

void main() {
  late AutoLogin login;

  setUp(() => login = AutoLogin(const Credentials('alice', 's3cret')));

  test('sends the id at the id prompt, then the password at the password prompt', () {
    expect(login.state, AutoLoginState.waitingForId);
    expect(login.onCursorRow(''), isNull);
    expect(login.onCursorRow(idPrompt), 'alice\r');
    expect(login.state, AutoLoginState.waitingForPassword);
    expect(login.onCursorRow(passwordPrompt), 's3cret\r');
    expect(login.state, AutoLoginState.done);
    expect(login.active, isFalse);
  });

  test('the id is sent only once while the prompt stays on screen', () {
    expect(login.onCursorRow(idPrompt), 'alice\r');
    expect(login.onCursorRow(idPrompt), isNull);
    expect(login.onCursorRow('$idPrompt alice'), isNull);
  });

  test('the password is never sent before the id', () {
    expect(login.onCursorRow(passwordPrompt), isNull);
    expect(login.state, AutoLoginState.waitingForId);
  });

  // Review Focus 1
  test('password is not sent to a row that merely mentions it', () {
    login.onCursorRow(idPrompt);
    expect(
      login.onCursorRow('忘記密碼可參考 https://www.ptt.cc/bbs/ID_GetBack/M.1.A.html'),
      isNull,
    );
    expect(login.onCursorRow('密碼'), isNull);
    expect(login.onCursorRow('請輸入代號'), isNull);
    expect(login.state, AutoLoginState.waitingForPassword);
  });

  // Review Focus 2
  test('does not retry after a failed login', () {
    login.onCursorRow(idPrompt);
    login.onCursorRow(passwordPrompt);
    expect(login.onCursorRow('密碼不對或無此帳號。請檢查大小寫及有無輸入錯誤。'), isNull);
    expect(login.onCursorRow(idPrompt), isNull);
    expect(login.onCursorRow(passwordPrompt), isNull);
    expect(login.state, AutoLoginState.done);
  });

  test('giving up stops everything', () {
    login.giveUp();
    expect(login.state, AutoLoginState.gaveUp);
    expect(login.active, isFalse);
    expect(login.onCursorRow(idPrompt), isNull);
    expect(login.onCursorRow(passwordPrompt), isNull);
  });

  test('giving up between id and password withholds the password', () {
    login.onCursorRow(idPrompt);
    login.giveUp();
    expect(login.onCursorRow(passwordPrompt), isNull);
  });

  test('giving up after success leaves the state as done', () {
    login.onCursorRow(idPrompt);
    login.onCursorRow(passwordPrompt);
    login.giveUp();
    expect(login.state, AutoLoginState.done);
  });

  test('user id validation', () {
    expect(isValidUserId('alice'), isTrue);
    expect(isValidUserId('A1b2C3d4E5f6'), isTrue);
    expect(isValidUserId(''), isFalse);
    expect(isValidUserId('A1b2C3d4E5f6g'), isFalse);
    expect(isValidUserId('al ice'), isFalse);
    expect(isValidUserId('alice\r'), isFalse);
    expect(isValidUserId('愛麗絲'), isFalse);
  });
}
