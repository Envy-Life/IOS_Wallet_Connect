import 'package:flutter_test/flutter_test.dart';

import 'package:ios_wallet_connect/ios_wallet_connect.dart';

void main() {
  test('package works', () {
    IosWalletConnect(
        appUrl: "envylife.dev", deepLinkUrl: "https://envylife.dev");
  });
}
