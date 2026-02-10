import 'dart:convert';
import 'dart:developer';
import 'package:artemis_port_util/artemis_port_util.dart';
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
  List<ArtemisPortDevice> printers = [];

  @override
  void initState() {
    super.initState();
    initPorts();
  }

  void initPorts() {
    setState(() => availablePorts = ArtemisPortUtil.getPorts);
    setState(
      () => printers = ArtemisPortUtil.getPorts
          .map(
            (a) => ArtemisPortDevice(
              portName: a,
              config: ArtemisPortDeviceSetting(portName: a, baudRate: BaudRate.br_115200, handshake: Handshake.none,dataBits: DataBits.db_8,stopBits: StopBits.one),
            ),
          )
          .toList(),
    );
  }

  void testQuery() async {
    // Example: DLE EOT 4 (0x10 0x04 0x04) — ask paper roll status.
  }

  // Future<dynamic> portPrint(ArtemisSerialPort port) async {
  //   final result = await port.printData("SQ");
  //   // final result = await port.queryStatus();
  //   log(result.toString());
  //   // log(result.text??'');
  //   return result;
  // }

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
                // ...printers
                //     .map((p) => p.asBarcodeReader)
                //     .map(
                //       (bc) {
                //         return ListTile(
                //         title: Text(bc.portName),
                //         subtitle: Row(
                //           spacing: 12,
                //           children: [
                //             TextButton(
                //               onPressed: () async {
                //                 await bc.disconnect();
                //               },
                //               child: Text("close"),
                //             ),
                //                     ValueListenableBuilder(valueListenable: bc.portStatus, builder: (BuildContext context, PortStatus value, Widget? child) {
                //                       return Text(value.name);
                //                     },),
                //                     ValueListenableBuilder(valueListenable: bc.barcodeReaderStatus, builder: (BuildContext context, BarcodeReaderStatus value, Widget? child) {
                //                       return Text(value.name);
                //                     },),
                //           ],
                //         ),
                //         onTap: () async {
                //           try {
                //             log("Trying to set ${bc.portName} as barcode reader");
                //
                //             // Use the getter from your existing portDevice instance
                //
                //             // You can still configure it if needed, but it's better to do this when creating the ArtemisPortDevice
                //             // If you must reconfigure, you might need to add a method for it.
                //             // For now, let's assume the initial config is correct.
                //
                //             // Listen to the status to see it change
                //             bc.connectionStatus.addListener(() {
                //               log("Reader status updated: ${bc.currentConnectionStatus}");
                //             });
                //
                //             if (await bc.connect()) {
                //               // connect() is the unified method from the interface
                //               bc.startListening();
                //               bc.onBarcode.listen((d) {
                //                 log("Barcode scanned: $d");
                //               });
                //             }
                //           } catch (e) {
                //             if(e is Error){
                //               log(e.stackTrace.toString());
                //             }
                //             log("Error setting up barcode reader: $e");
                //           }
                //         },
                //         trailing: bc.icon(24),
                //       );
                //       },
                //     ),


                ...printers
                    .map((p) => p.asPrinter)
                    .map(
                      (bp) => ListTile(
                    title: Text(bp.portName),
                    subtitle: Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            await bp.initIt();
                          },
                          child: Text("init"),
                        ),
                        TextButton(
                          onPressed: () async {
                            await bp.setBtPec();
                          },
                          child: Text("set pec"),
                        ),
                        TextButton(
                          onPressed: () async {
                            await bp.testPrintTag();
                          },
                          child: Text("test bt"),
                        ),
                        // TextButton(
                        //   onPressed: () async {
                        //     bp.startMonitoring();
                        //   },
                        //   child: Text("start monitoring"),
                        // ),
                        TextButton(
                          onPressed: () async {
                            await bp.disconnect();
                          },
                          child: Text("close"),
                        ),
                        TextButton(
                          onPressed: () async {
                            final s = bp.portStatus.value;
                            log(s.name);
                          },
                          child: Text("get port sttatus"),
                        ),
                        ValueListenableBuilder(valueListenable: bp.portStatus, builder: (BuildContext context, PortStatus value, Widget? child) {
                          return Text(value.name);
                        },),
                        ValueListenableBuilder(valueListenable: bp.statusListenable, builder: (BuildContext context, DeviceStatus value, Widget? child) {
                          return Text(value.desc);
                        },),
                      ],
                    ),
                    onTap: () async {

                      // ArtemisPortPrinter p = ArtemisPortPrinter(portName: bp.portName);
                      // p.connect();
                      // p.portStatus.addListener((){
                      //   log("port status changed ${p.portStatus.value.name}");
                      // });

                      try {
                        await bp.connect();
                        await bp.initIt();
                        // bp.startMonitoring();
                      } catch (e) {
                        log("Error setting up printer: $e");
                      }
                    },
                    trailing: bp.icon(24),
                  ),
                ),
                // ...printers.map((portDevice){
                //   final port = portDevice.portName;
                //   return  ExpansionTile(
                //     leading: IconButton(
                //       onPressed: () async {
                //         portDevice.asPrinter.connect();
                //         // ArtemisPortPrint.log(port, "AV");
                //         //
                //         //                         final response = await ArtemisPortPrint.sendAndWait(
                //         //                           port,
                //         //                           request: [0x10, 0x04, 0x04], // e.g., ESC/POS DLE EOT 4 (paper status)
                //         //                           timeout: const Duration(seconds: 1),
                //         //                         );
                //         //
                //         // // Decide: timeout/no-response
                //         //                         if (response.isEmpty) {
                //         //                           // handle no response
                //         //                           log("no response");
                //         //                         } else {
                //         //                           log("parse response");
                //         //                           // parse response bytes
                //         //                         }
                //         //                         await ArtemisPortPrint.printBytesToCom(portName: 'COM3', bytes:utf8.encode("AV"));
                //         //                       testQuery();
                //         // portPrint(port);
                //         // port.queryStatus();
                //         // SerialProbe().test6();
                //       },
                //       icon: Icon(Icons.home),
                //     ),
                //     title: Row(
                //       children: [
                //         Text(portDevice.portName),
                //         TextButton(
                //           onPressed: () {
                //             // portPrint(port);
                //
                //             portDevice.asPrinter.testQuery();
                //           },
                //           child: Text("port print"),
                //         ),
                //         TextButton(
                //           onPressed: () async {
                //             try {
                //               log("Trying to set ${portDevice.portName} as barcode reader");
                //
                //               // Use the getter from your existing portDevice instance
                //               final reader = portDevice.asBarcodeReader;
                //
                //               // You can still configure it if needed, but it's better to do this when creating the ArtemisPortDevice
                //               // If you must reconfigure, you might need to add a method for it.
                //               // For now, let's assume the initial config is correct.
                //
                //               // Listen to the status to see it change
                //               reader.connectionStatus.addListener(() {
                //                 log("Reader status updated: ${reader.currentConnectionStatus}");
                //               });
                //
                //               if (await reader.connect()) { // connect() is the unified method from the interface
                //                 reader.startListening();
                //                 reader.onBarcode.listen((d) {
                //                   log("Barcode scanned: $d");
                //                 });
                //               }
                //             } catch (e) {
                //               log("Error setting up barcode reader: $e");
                //             }
                //
                //           },
                //           child: Row(
                //             children: [
                //               Text("set as br"),
                //
                //             ],
                //           ),
                //         ),
                //         Builder(
                //           builder: (BuildContext context) {
                //             final listenable = portDevice.asBarcodeReader.statusImagePath;
                //             log("device status ${listenable.value}");
                //             return ValueListenableBuilder<String>(
                //               valueListenable: listenable,
                //               builder: (context, status, _) {
                //                return Image.asset(status, width: 24, package: 'artemis_port_util');
                //               },
                //             );
                //           },
                //         ),
                //         portDevice.asBarcodeReader.icon(),
                //         Builder(
                //           builder: (BuildContext context) {
                //             final listenable = portDevice.asPrinter.statusListenable;
                //
                //             return ValueListenableBuilder<DeviceStatus>(
                //               valueListenable: listenable,
                //               builder: (context, status, _) {
                //                 switch (status.state) {
                //                   case StatusState.online:
                //                     return const Text('🟢 Ready');
                //                   case StatusState.busy:
                //                     return const Text('🖨 Printing…');
                //                   case StatusState.paperOut:
                //                     return const Text('📄❌ Paper out');
                //                   case StatusState.paperJam:
                //                     return const Text('🧩 Paper jam');
                //                   case StatusState.printHeadLifted:
                //                     return const Text('🔧 Head lifted');
                //                   case StatusState.offline:
                //                     return const Text('🔴 Offline');
                //                   case StatusState.unknown:
                //                     return Text('❔ ${status.desc}');
                //                 }
                //               },
                //             );
                //           },
                //         ),
                //         // ValueListenableBuilder(
                //         //   valueListenable: port.status,
                //         //   builder: (context, PrinterStatus status, _) {
                //         //     switch (status) {
                //         //       case PrinterStatus.offline:
                //         //         return TextButton(
                //         //           onPressed: () {
                //         //             port.connect();
                //         //
                //         //           },
                //         //           child: Text("Connect"),
                //         //
                //         //         );
                //         //       case PrinterStatus.ready:
                //         //         return TextButton(
                //         //           onPressed: () {
                //         //             port.disconnect();
                //         //           },
                //         //           child: Text("Disconnect"),
                //         //         );
                //         //       case PrinterStatus.printing:
                //         //         return const Text("🖨 Printing...");
                //         //       case PrinterStatus.waiting:
                //         //         return const Text("⌛ Waiting response...");
                //         //       case PrinterStatus.error:
                //         //         return const Text("⚠️ Error");
                //         //       case PrinterStatus.connecting:
                //         //         return const Text("🔄 Connecting...");
                //         //     }
                //         //   },
                //         //
                //         // ),
                //       ],
                //     ),
                //     trailing: Builder(
                //       builder: (BuildContext context) {
                //         final listenable = portDevice.asPrinter.connectionStatus;
                //
                //         return ValueListenableBuilder<DeviceConnectionStatus>(
                //           valueListenable: listenable,
                //           builder: (context, status, _) {
                //
                //             return Text(status.name);
                //           },
                //         );
                //       },
                //     ),
                //
                //     children: [
                //       // CardListTile('Description', port.description, port),
                //       // CardListTile('Transport', port.transport.toTransport(), port),
                //       // CardListTile('USB Bus', port.busNumber?.toPadded(), port),
                //       // CardListTile('USB Device', port.deviceNumber?.toPadded(), port),
                //       // CardListTile('Vendor ID', port.vendorId?.toHex(), port),
                //       // CardListTile('Product ID', port.productId?.toHex(), port),
                //       // CardListTile('Manufacturer', port.manufacturer, port),
                //       // CardListTile('Product Name', port.productName, port),
                //       // CardListTile('Serial Number', port.serialNumber, port),
                //       // CardListTile('MAC Address', port.macAddress, port),
                //     ],
                //   );
                // })
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(child: Icon(Icons.refresh), onPressed: initPorts),
    );
  }
}

class CardListTile extends StatelessWidget {
  final String name;
  final String? value;
  final SerialPort? port;

  const CardListTile(this.name, this.value, this.port, {super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(title: Text("value" ?? 'N/A'), subtitle: Text(name), onTap: () {}),
    );
  }
}
