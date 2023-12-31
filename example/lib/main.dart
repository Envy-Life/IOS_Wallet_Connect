import 'package:flutter/material.dart';
import 'package:pinenacl/x25519.dart';
import 'package:ios_wallet_connect/ios_wallet_connect.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IOS_Wallet_Connect Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'IOS_Wallet_Connect Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var client =
      IosWalletConnect(appUrl: "https://dreader.io", deepLinkUrl: "soltest://");

  @override
  void initState() {
    client.init();
    super.initState();
  }

  Widget Button(Function onPressed, String name) {
    return ElevatedButton(
      onPressed: () {
        onPressed();
      },
      child: Text(name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Button(() async {
              var session = await client.connect(cluster: "devnet");
              print(session);
            }, "Connect"),
            const SizedBox(height: 10),
            Button(() async {
              var session = await client.signTransaction(
                  transaction: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]));
              print(session);
            }, "Sign Transaction"),
            const SizedBox(height: 10),
            Button(() async {
              var session = await client.signAllTransactions(transactions: [
                Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9])
              ]);
              print(session);
            }, "Sign All Transactions"),
            const SizedBox(height: 10),
            Button(() async {
              var session = await client.signAndSendTransaction(
                  transaction: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]));
              print(session);
            }, "Sign and Send Transaction"),
            const SizedBox(height: 10),
            Button(() async {
              var session = await client.connect(cluster: "devnet");
              print(session);
            }, "Sign Message"),
            const SizedBox(height: 10),
            Button(() async {
              await client.disConnect();
            }, "Disconnect"),
          ],
        ),
      ),
    );
  }
}
