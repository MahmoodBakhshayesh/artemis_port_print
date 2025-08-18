import 'dart:convert';
import 'dart:developer';

import 'package:artemis_port_print/artemis_port_print.dart';
import 'package:artemis_port_print/util.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var availablePorts = [];

  @override
  void initState() {
    super.initState();
    initPorts();
  }

  void initPorts() {
    setState(() => availablePorts = ArtemisPortPrint.getPorts);
  }

  void testQuery() async {
    // Example: DLE EOT 4 (0x10 0x04 0x04) — ask paper roll status.



  }

  Future<PrintResult> portPrint(ArtemisSerialPort port) async {
    final result = await port.printData("AV");
    log(result.status.name);
    log(result.text??'');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                for (final address in availablePorts)
                  Builder(builder: (context) {
                    final port = ArtemisPortPrint.createSerialPort(address);
                    return ExpansionTile(
                      leading: IconButton(onPressed: () async {
                        // ArtemisPortPrint.log(port, "AV");
//
//                         final response = await ArtemisPortPrint.sendAndWait(
//                           port,
//                           request: [0x10, 0x04, 0x04], // e.g., ESC/POS DLE EOT 4 (paper status)
//                           timeout: const Duration(seconds: 1),
//                         );
//
// // Decide: timeout/no-response
//                         if (response.isEmpty) {
//                           // handle no response
//                           log("no response");
//                         } else {
//                           log("parse response");
//                           // parse response bytes
//                         }
//                         await ArtemisPortPrint.printBytesToCom(portName: 'COM3', bytes:utf8.encode("AV"));
//                       testQuery();
                      print(port);
                      // SerialProbe().test6();

                      }, icon: Icon(Icons.home)),
                      title: Text(address),
                      children: [
                        CardListTile('Description', port.description,port),
                        CardListTile('Transport', port.transport.toTransport(),port),
                        CardListTile('USB Bus', port.busNumber?.toPadded(),port),
                        CardListTile('USB Device', port.deviceNumber?.toPadded(),port),
                        CardListTile('Vendor ID', port.vendorId?.toHex(),port),
                        CardListTile('Product ID', port.productId?.toHex(),port),
                        CardListTile('Manufacturer', port.manufacturer,port),
                        CardListTile('Product Name', port.productName,port),
                        CardListTile('Serial Number', port.serialNumber,port),
                        CardListTile('MAC Address', port.macAddress,port),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.refresh),
        onPressed: initPorts,
      ),
    );
  }
}

class CardListTile extends StatelessWidget {
  final String name;
  final String? value;
  final SerialPort? port;

  const CardListTile(this.name, this.value,this.port, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(value ?? 'N/A'),
        subtitle: Text(name),
        onTap: (){

        },
      ),
    );
  }
}