import 'dart:async';
import 'dart:convert';

import 'package:pinenacl/x25519.dart';
import 'package:solana/base58.dart';

import 'package:hive/hive.dart' as hive;
import 'package:uni_links/uni_links.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:path_provider/path_provider.dart';

const String iosWalletStoreName = 'com.EnvyLife.IOSWalletStore';

class IosWalletStore {
  static hive.Box get instance => hive.Hive.box(iosWalletStoreName);

  init() async {
    var appDir = await getApplicationDocumentsDirectory();
    hive.Hive.init(appDir.path);
    await hive.Hive.openBox(iosWalletStoreName);
  }
}

class IosWalletStoreModel {
  late PrivateKey dAppSecretKey;
  late PublicKey dAppPublicKey;
  String? sessionToken;
  String? userPublicKey;
  PublicKey? walletPublicKey;

  IosWalletStoreModel({
    required String dAppSecretKey,
    required String dAppPublicKey,
    this.sessionToken,
    this.userPublicKey,
    String? walletPublicKey,
  }) {
    this.dAppSecretKey =
        PrivateKey(Uint8List.fromList(base58decode(dAppSecretKey)));
    this.dAppPublicKey =
        PublicKey(Uint8List.fromList(base58decode(dAppPublicKey)));
    if (walletPublicKey != null) {
      this.walletPublicKey =
          PublicKey(Uint8List.fromList(base58decode(walletPublicKey)));
    }
  }

  factory IosWalletStoreModel.fromJson(Map<dynamic, dynamic> json) {
    return IosWalletStoreModel(
      dAppSecretKey: json['dAppSecretKey'],
      dAppPublicKey: json['dAppPublicKey'],
      sessionToken: json['sessionToken'],
      userPublicKey: json['userPublicKey'],
      walletPublicKey: json['walletPublicKey'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dAppSecretKey': base58encode(dAppSecretKey.asTypedList),
      'dAppPublicKey': base58encode(dAppPublicKey.asTypedList),
      'sessionToken': sessionToken,
      'userPublicKey': userPublicKey,
      'walletPublicKey': walletPublicKey != null
          ? base58encode(Uint8List.fromList(walletPublicKey!))
          : null,
    };
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  void setSessionToken(String? sessionToken) {
    this.sessionToken = sessionToken;
  }

  void setUserPublicKey(String? userPublicKey) {
    this.userPublicKey = userPublicKey;
  }

  void setWalletPublicKey(PublicKey? walletPublicKey) {
    this.walletPublicKey = walletPublicKey;
  }
}

class IosWalletConnect {
  final String appUrl;
  final String deepLinkUrl;
  IosWalletStoreModel? _model;
  late Box? _sharedSecret;

  IosWalletConnect({
    required this.appUrl,
    required this.deepLinkUrl,
  });

  Future<void> init() async {
    await populateIosWalletStore();
    if (_model!.sessionToken != null) {
      createSharedSecret(_model!.walletPublicKey!.toUint8List());
    }
  }

  Future<void> populateIosWalletStore() async {
    await IosWalletStore().init();
    final store = IosWalletStore.instance;
    if (store.isEmpty) {
      final keyPair = PrivateKey.generate();
      final dAppSecretKey = base58encode(keyPair);
      final dAppPublicKey = base58encode(keyPair.publicKey);
      final model = IosWalletStoreModel(
        dAppSecretKey: dAppSecretKey,
        dAppPublicKey: dAppPublicKey,
      );
      await store.put('model', model.toJson());
    }
    _model = IosWalletStoreModel.fromJson((store.get('model')));
  }

  Future<Map?> connect({
    required String cluster,
    String wallet = "phantom.app",
    String path = "/ul/v1/connect",
    String? redirect,
  }) async {
    final uri =
        Uri(scheme: 'https', host: wallet, path: path, queryParameters: {
      'cluster': cluster,
      'dapp_encryption_public_key':
          base58encode(_model!.dAppPublicKey.asTypedList),
      'app_url': appUrl,
      'redirect_link': '$deepLinkUrl${redirect ?? '/iosWalletConnect'}',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (redirect == null) {
      var recievedUri = "";
      var error;
      StreamSubscription _sub = uriLinkStream.listen((Uri? uri) {
        recievedUri = uri.toString();
      }, onError: (Object err) {
        error = err;
      });

      if (error != null) {
        await _sub.cancel();

        throw error;
      }

      int tries = 10;
      while (recievedUri == "" && tries-- > 0) {
        await Future.delayed(Duration(seconds: 3));
      }

      await _sub.cancel();

      if (recievedUri == "") {
        throw Exception('No response from wallet');
      }

      recievedUri = recievedUri.substring(recievedUri.indexOf('?') + 1);

      Map retMap = Uri.splitQueryString(recievedUri);

      if (retMap['errorMessage'] != null) {
        await uriLinkStream.drain(1);
        throw Exception(retMap['errorMessage']);
      }

      print(retMap[
          '${wallet.substring(0, wallet.indexOf('.'))}_encryption_public_key']!);

      createSharedSecret(Uint8List.fromList(base58decode(retMap[
          '${wallet.substring(0, wallet.indexOf('.'))}_encryption_public_key']!)));
      retMap = {
        ...retMap,
        ...decryptPayload(
          data: retMap["data"]!,
          nonce: retMap["nonce"]!,
        ),
      };

      _model!.setSessionToken(retMap['session']);
      _model!.setUserPublicKey(retMap['public_key']);
      _model!.setWalletPublicKey(PublicKey(Uint8List.fromList(base58decode(retMap[
          '${wallet.substring(0, wallet.indexOf('.'))}_encryption_public_key']!))));
      await IosWalletStore.instance.put('model', _model!.toJson());

      return retMap;
    } else {
      return null;
    }
  }

  Future<void> disConnect({
    String wallet = "phantom.app",
    String path = "/ul/v1/disconnect",
    String? redirect,
  }) async {
    final payload = encryptPayload({
      "session": _model!.sessionToken,
    });
    final uri = Uri(
      scheme: 'https',
      host: wallet,
      path: path,
      queryParameters: {
        'payload': base58encode(payload['encryptedPayload']),
        'dapp_encryption_public_key':
            base58encode(_model!.dAppPublicKey.asTypedList),
        'nonce': base58encode(payload['nonce']),
        'redirect_link': '$deepLinkUrl${redirect ?? '/iosWalletConnect'}',
      },
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (redirect == null) {
      var recievedUri = "";
      var error;
      StreamSubscription _sub = uriLinkStream.listen((Uri? uri) {
        recievedUri = uri.toString();
      }, onError: (Object err) {
        error = err;
      });

      if (error != null) {
        await _sub.cancel();

        throw error;
      }

      int tries = 10;
      while (recievedUri == "" && tries-- > 0) {
        await Future.delayed(Duration(seconds: 3));
      }

      if (recievedUri == "") {
        throw Exception('No response from wallet');
      }

      recievedUri = recievedUri.substring(recievedUri.indexOf('?') + 1);

      Map retMap = Uri.splitQueryString(recievedUri);

      if (retMap['errorMessage'] != null) {
        throw Exception(retMap['errorMessage']);
      }

      _model!.setSessionToken(null);
      _model!.setUserPublicKey(null);
      _model!.setWalletPublicKey(null);
      IosWalletStore.instance.put('model', _model!.toJson());

      await _sub.cancel();

      return;
    } else {
      return;
    }
  }

  Future<Map?> signTransaction({
    String wallet = "phantom.app",
    String path = "/ul/v1/signTransaction",
    String? redirect,
    required Uint8List transaction,
  }) async {
    final payload = encryptPayload({
      "session": _model!.sessionToken,
      "transaction": base58encode(transaction),
    });
    final uri = Uri(
      scheme: 'https',
      host: wallet,
      path: path,
      queryParameters: {
        'payload': base58encode(payload['encryptedPayload']),
        'nonce': base58encode(payload['nonce']),
        'dapp_encryption_public_key':
            base58encode(_model!.dAppPublicKey.asTypedList),
        'redirect_link': '$deepLinkUrl${redirect ?? '/iosWalletConnect'}',
      },
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (redirect == null) {
      var recievedUri = "";
      var error;
      StreamSubscription _sub = uriLinkStream.listen((Uri? uri) {
        recievedUri = uri.toString();
      }, onError: (Object err) {
        error = err;
      });

      if (error != null) {
        await _sub.cancel();

        throw error;
      }

      int tries = 10;
      while (recievedUri == "" && tries-- > 0) {
        await Future.delayed(Duration(seconds: 3));
      }

      await _sub.cancel();

      if (recievedUri == "") {
        throw Exception('No response from wallet');
      }

      recievedUri = recievedUri.substring(recievedUri.indexOf('?') + 1);

      Map retMap = Uri.splitQueryString(recievedUri);

      if (retMap['errorMessage'] != null) {
        throw Exception(retMap['errorMessage']);
      }

      retMap = {
        ...retMap,
        ...decryptPayload(
          data: retMap["data"]!,
          nonce: retMap["nonce"]!,
        ),
      };

      return retMap;
    } else {
      return null;
    }
  }

  Future<Map?> signAllTransactions({
    String wallet = "phantom.app",
    String path = "/ul/v1/signAllTransactions",
    String? redirect,
    required List<Uint8List> transactions,
  }) async {
    final payload = encryptPayload({
      "session": _model!.sessionToken,
      "transactions": transactions.map((e) => base58encode(e)).toList(),
    });
    final uri = Uri(
      scheme: 'https',
      host: wallet,
      path: path,
      queryParameters: {
        'payload': base58encode(payload['encryptedPayload']),
        'nonce': base58encode(payload['nonce']),
        'dapp_encryption_public_key':
            base58encode(_model!.dAppPublicKey.asTypedList),
        'redirect_link': '$deepLinkUrl${redirect ?? '/iosWalletConnect'}',
      },
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (redirect == null) {
      var recievedUri = "";
      var error;
      StreamSubscription _sub = uriLinkStream.listen((Uri? uri) {
        recievedUri = uri.toString();
      }, onError: (Object err) {
        error = err;
      });

      if (error != null) {
        await _sub.cancel();

        throw error;
      }

      int tries = 10;
      while (recievedUri == "" && tries-- > 0) {
        await Future.delayed(Duration(seconds: 3));
      }

      await _sub.cancel();

      if (recievedUri == "") {
        throw Exception('No response from wallet');
      }

      recievedUri = recievedUri.substring(recievedUri.indexOf('?') + 1);

      Map retMap = Uri.splitQueryString(recievedUri);

      if (retMap['errorMessage'] != null) {
        throw Exception(retMap['errorMessage']);
      }

      retMap = {
        ...retMap,
        ...decryptPayload(
          data: retMap["data"]!,
          nonce: retMap["nonce"]!,
        ),
      };

      return retMap;
    } else {
      return null;
    }
  }

  Future<Map?> signAndSendTransaction({
    String wallet = "phantom.app",
    String path = "/ul/v1/signAndSendTransaction",
    String? redirect,
    required Uint8List transaction,
    String? sendOptions,
  }) async {
    final payload = encryptPayload({
      "session": _model!.sessionToken,
      "transactions": base58encode(transaction),
      "sendOptions": sendOptions,
    });

    final uri = Uri(
      scheme: 'https',
      host: wallet,
      path: path,
      queryParameters: {
        'payload': base58encode(payload['encryptedPayload']),
        'nonce': base58encode(payload['nonce']),
        'dapp_encryption_public_key':
            base58encode(_model!.dAppPublicKey.asTypedList),
        'redirect_link': '$deepLinkUrl${redirect ?? '/iosWalletConnect'}',
      },
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (redirect == null) {
      var recievedUri = "";
      var error;
      StreamSubscription _sub = uriLinkStream.listen((Uri? uri) {
        recievedUri = uri.toString();
      }, onError: (Object err) {
        error = err;
      });

      if (error != null) {
        await _sub.cancel();
        throw error;
      }

      int tries = 10;
      while (recievedUri == "" && tries-- > 0) {
        await Future.delayed(Duration(seconds: 3));
      }

      await _sub.cancel();

      if (recievedUri == "") {
        throw Exception('No response from wallet');
      }

      recievedUri = recievedUri.substring(recievedUri.indexOf('?') + 1);

      Map retMap = Uri.splitQueryString(recievedUri);

      if (retMap['errorMessage'] != null) {
        await uriLinkStream.drain(1);
        throw Exception(retMap['errorMessage']);
      }

      retMap = {
        ...retMap,
        ...decryptPayload(
          data: retMap["data"]!,
          nonce: retMap["nonce"]!,
        ),
      };

      return retMap;
    } else {
      return null;
    }
  }

  Future<Map?> signMessage({
    String wallet = "phantom.app",
    String path = "/ul/v1/signMessage",
    String? redirect,
    required Uint8List message,
    String display = 'utf8',
  }) async {
    final payload = encryptPayload({
      "session": _model!.sessionToken,
      "message": base58encode(message),
      "display": display,
    });

    final uri = Uri(
      scheme: 'https',
      host: wallet,
      path: path,
      queryParameters: {
        'payload': base58encode(payload['encryptedPayload']),
        'nonce': base58encode(payload['nonce']),
        'dapp_encryption_public_key':
            base58encode(_model!.dAppPublicKey.asTypedList),
        'redirect_link': '$deepLinkUrl${redirect ?? '/iosWalletConnect'}',
      },
    );

    await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (redirect == null) {
      var recievedUri = "";
      var error;
      StreamSubscription _sub = uriLinkStream.listen((Uri? uri) {
        recievedUri = uri.toString();
      }, onError: (Object err) {
        error = err;
      });

      if (error != null) {
        await _sub.cancel();

        throw error;
      }

      int tries = 10;
      while (recievedUri == "" && tries-- > 0) {
        await Future.delayed(Duration(seconds: 3));
      }

      await _sub.cancel();

      if (recievedUri == "") {
        throw Exception('No response from wallet');
      }

      recievedUri = recievedUri.substring(recievedUri.indexOf('?') + 1);

      Map retMap = Uri.splitQueryString(recievedUri);

      if (retMap['errorMessage'] != null) {
        throw Exception(retMap['errorMessage']);
      }

      retMap = {
        ...retMap,
        ...decryptPayload(
          data: retMap["data"]!,
          nonce: retMap["nonce"]!,
        ),
      };

      return retMap;
    } else {
      return null;
    }
  }

  /// Thanks to phantom-connect package for this method
  /// Created a shared secret between Phantom Wallet and our DApp using our [_dAppSecretKey] and [${wallet}_encryption_public_key].
  ///
  /// - `${wallet}_encryption_public_key` is the public key of Wallet.
  void createSharedSecret(Uint8List remotePubKey) async {
    _sharedSecret = Box(
      myPrivateKey: _model!.dAppSecretKey,
      theirPublicKey: PublicKey(remotePubKey),
    );
  }

  /// Thanks to phantom-connect package for this method
  /// Decrypts the [data] payload returned by Wallet
  ///
  /// - Using [nonce] we generated on server side and [dAppSecretKey] we decrypt the encrypted data.
  /// - Returns the decrypted `payload` as a `Map<dynamic, dynamic>`.
  Map<dynamic, dynamic> decryptPayload({
    required String data,
    required String nonce,
  }) {
    if (_sharedSecret == null) {
      throw Exception('Shared secret not created');
    }

    final decryptedData = _sharedSecret?.decrypt(
      ByteList(base58decode(data)),
      nonce: Uint8List.fromList(base58decode(nonce)),
    );

    Map payload =
        const JsonDecoder().convert(String.fromCharCodes(decryptedData!));
    return payload;
  }

  /// Thanks to phantom-connect package for this method
  /// Encrypts the data payload to be sent to  Wallet.
  ///
  /// - Returns the encrypted `payload` and `nonce`.
  Map<String, dynamic> encryptPayload(Map<String, dynamic> data) {
    if (_sharedSecret == null) {
      throw Exception('Shared secret not created');
    }
    var nonce = PineNaClUtils.randombytes(24);
    var payload = jsonEncode(data).codeUnits;
    var encryptedPayload =
        _sharedSecret?.encrypt(payload.toUint8List(), nonce: nonce).cipherText;
    return {"encryptedPayload": encryptedPayload?.asTypedList, "nonce": nonce};
  }
}
