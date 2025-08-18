# artemis_port_print

A pragmatic **request → response queue** for serial printers and devices over COM ports in Flutter/Dart, powered by [`flutter_libserialport`].  
It handles **write**, **waits for a reply or timeout**, and returns a rich `PrintResult` (status + raw bytes + decoded text).  
Includes optional **STX/ETX framing** support (DLE escaping) so your subscribers receive **payload-only** data.

> Built for apps that send a command and expect “OK/ERR/…” (or any response) per request.

---

## ✨ What’s inside

- 🔁 **Queued I/O** — each request waits for a response or a timeout (ordered, one-at-a-time)
- ⏱️ **Timeout + quiet window** — end-of-message detection without fixed lengths
- 🧾 **Rich result** — `PrintResult { status, text?, bytes? }`
- 🧩 **Classifier hook** — decide OK/ERROR/UNKNOWN based on your device’s payload
- 🧱 Optional **STX/ETX** framing (with **DLE** escape) — you only see payload (no `0x02`/`0x03`)
- 🧲 Handy helpers: list ports, open/close, send text or bytes

---

## 📦 Install

Add to `pubspec.yaml`:

```yaml
dependencies:
  artemis_port_print: ^1.0.0
```

> `flutter_libserialport` supports Windows/Linux/macOS. On Windows you’ll typically talk to `COMx`.

---

## 🧰 Core concepts

- **Ports** are surfaced by `ArtemisPortPrint.getPorts` (e.g., `["COM3", "COM4"]`).
- **Open once, reuse**: keep a port open across multiple `printData` calls for performance and stability.
- **One request at a time**: calls queue internally (send → wait/timeout → classify → next).

---

## 🚀 Quick Start

### 1) List ports in your UI

```dart
var availablePorts = <String>[];

@override
void initState() {
  super.initState();
  initPorts();
}

void initPorts() {
  setState(() => availablePorts = ArtemisPortPrint.getPorts);
}
```

### 2) Open a port and print

```dart
Future<PrintResult> portPrint(ArtemisSerialPort port) async {
  final result = await port.printData("AV"); // send text (UTF-8)
  // result.status ∈ { ok, error, unknown, timeout }
  // result.text   → decoded payload (if any)
  // result.bytes  → raw payload (if any)
  return result;
}
```

Typical usage with selection (pseudo-UI):
```dart
final port = ArtemisSerialPort("COM4",
  baudRate: 9600,
  dataBits: 8,
  parity: 0,
  stopBits: 1,
  flowControl: SerialPortFlowControl.none,
  framed: true, // if your device wraps replies with STX/ETX
);

await port.open(); // keep open while your screen is active
final res = await port.printData("AV");
print("Status: ${res.status}  Text: ${res.text}");
await port.close();
```

---

## 🧪 Return type

```dart
enum PrintStatus { ok, error, unknown, timeout }

class PrintResult {
  final PrintStatus status; // ok/error/unknown/timeout
  final String? text;       // decoded payload, if any
  final Uint8List? bytes;   // raw payload, if any
}
```

### Built-in classifier
By default the package maps common tokens:
- **OK**: contains `OK`, `EPOK`, or `ESOK`
- **ERROR**: contains `ERR`, `ERROR`, or `NOK`
- **UNKNOWN**: any non-empty payload that doesn’t match ok/error
- **TIMEOUT**: no payload before timeout

You can provide a custom classifier when constructing the queue/port, e.g.:
```dart
classifier: (bytes, text) {
  final t = text.toUpperCase();
  if (t.startsWith('HDCAVOK'))  return PrintStatus.ok;
  if (t.startsWith('HDCAVERR')) return PrintStatus.error;
  return bytes.isNotEmpty ? PrintStatus.unknown : PrintStatus.timeout;
}
```

---

## 🧱 Framing (STX/ETX + DLE)

If your device replies as:

```
02 48 44 43 41 56 4F 4B 30 39 23 42 50 50 03
   H  D  C  A  V  O  K  0  9  #  B  P  P
```

enable framed mode (`framed: true`). The parser strips `STX (0x02)` and `ETX (0x03)` and unescapes **DLE (0x10)** so your listeners/print results receive **payload only**:

```
48 44 43 41 56 4F 4B 30 39 23 42 50 50
H  D  C  A  V  O  K  0  9  #  B  P  P
```

If your device is raw (no framing), set `framed: false` (default) and the stream will pass through bytes as-is.

---

## 🔄 Ordered requests

Each `printData` (or raw send) is **serialized** internally:

```dart
final a = port.printData('CMD1\n');
final b = port.printData('CMD2\n');
final c = port.printData('CMD3\n');

// These execute in strict order: A → (reply/timeout) → B → (reply/timeout) → C ...
final r1 = await a;
final r2 = await b;
final r3 = await c;
```

---

## ⚙️ Configuration

```dart
final port = ArtemisSerialPort(
  "COM4",
  baudRate: 9600,
  dataBits: 8,
  parity: 0,        // none
  stopBits: 1,
  flowControl: SerialPortFlowControl.none, // try rtsCts/dtrDsr if required
  framed: true,     // enable STX/ETX payload parsing
  timeout: const Duration(seconds: 2),
  quietWindow: const Duration(milliseconds: 150),
  // classifier: your custom classifier, optional
);
```

- **timeout**: hard deadline — when reached you get `PrintStatus.timeout`
- **quietWindow**: message considered complete after this idle period
- **flowControl**: `none` | `xonXoff` | `rtsCts` | `dtrDsr` (select what the device expects)

> Note: `flutter_libserialport` doesn’t expose manual `setDTR/RTS`; use the flow control that matches your device.

---

## 🛠️ Troubleshooting

- **Access denied / busy**: some other app holds the port (Arduino monitor, PuTTY, vendor utility). Close it.
- **No response**:
    - Check **baud/parity/stop/flow** exactly match device settings.
    - Try hardware handshake: `rtsCts` or `dtrDsr`.
    - Some cables are TX-only; use a proper USB–serial that wires both TX and RX (and handshake pins if required).
    - Ensure your command actually elicits a reply (some printers don’t respond unless you send a status/query).
- **Seeing 0x02/0x03 in text**: enable `framed: true` (or set `stripFraming: true` in the queue).

---

## 🧷 Example widget snippet

```dart
class PortDemo extends StatefulWidget {
  const PortDemo({super.key});
  @override
  State<PortDemo> createState() => _PortDemoState();
}

class _PortDemoState extends State<PortDemo> {
  var availablePorts = <String>[];
  ArtemisSerialPort? _port;

  @override
  void initState() {
    super.initState();
    initPorts();
  }

  void initPorts() {
    setState(() => availablePorts = ArtemisPortPrint.getPorts);
  }

  Future<void> openSelected(String name) async {
    _port?.close();
    _port = ArtemisSerialPort(
      name,
      baudRate: 9600,
      dataBits: 8,
      parity: 0,
      stopBits: 1,
      flowControl: SerialPortFlowControl.none,
      framed: true,
      timeout: const Duration(seconds: 2),
      quietWindow: const Duration(milliseconds: 150),
    );
    await _port!.open();
  }

  Future<void> testQuery() async {
    if (_port == null) return;
    final r = await _port!.printData("AV");
    debugPrint('Status: ${r.status}  Text: ${r.text ?? ''}');
  }

  @override
  void dispose() {
    _port?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // build your UI (dropdown of availablePorts, open button, testQuery button)
    return const SizedBox.shrink();
  }
}
```

---

## 📜 License

MIT (recommended). Create a `LICENSE` file with the MIT text or your preferred license.

---

## 🙋 Support

Open an issue with:
- device model & exact serial settings,
- a short log of sent commands and received bytes,
- whether framing is enabled,
- OS version & adapter model.

We’ll help you tune the classifier/flow control quickly.

[`flutter_libserialport`]: https://pub.dev/packages/flutter_libserialport
