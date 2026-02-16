import 'dart:io';

class ArtemisLogger {
  final String deviceName;
  final File _logFile;
  final bool enableConsole;

  ArtemisLogger({
    required this.deviceName,
    String? logDirectory,
    this.enableConsole = true,
  }) : _logFile = File('${logDirectory ?? 'logs'}/artemis_log_${deviceName.replaceAll(RegExp(r'[^\w\.-]'), '_')}.txt');

  /// Get the underlying log file object.
  File get file => _logFile;

  /// Get the path to the log file.
  String get path => _logFile.path;

  Future<void> log(String level, String message) async {
    final now = DateTime.now();
    final timestamp = _formatDate(now);
    
    // Format: 
    // ================================================================================================
    // 2026-02-16 16:23:05,129 : DeviceName => (LEVEL) - Message
    
    final logEntry = '''
================================================================================================
$timestamp : $deviceName => ($level) - $message

''';

    if (enableConsole) {
      // print('$timestamp : $deviceName => ($level) - $message');
    }

    try {
      if (!_logFile.parent.existsSync()) {
        _logFile.parent.createSync(recursive: true);
      }
      await _logFile.writeAsString(logEntry, mode: FileMode.append);
    } catch (e) {
      if (enableConsole) print('Failed to write log: $e');
    }
  }
  
  void info(String message) => log('INFO', message);
  void debug(String message) => log('DEBUG', message);
  void error(String message) => log('ERROR', message);
  void warning(String message) => log('WARNING', message);

  String _formatDate(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)},${three(dt.millisecond)}';
  }
}
