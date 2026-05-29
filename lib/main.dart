import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WS Command Sender',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const CommandPage(),
    );
  }
}

class CommandPage extends StatefulWidget {
  const CommandPage({super.key});

  @override
  State<CommandPage> createState() => _CommandPageState();
}

class _CommandPageState extends State<CommandPage> {
  final _serverUrlCtrl = TextEditingController(text: 'ws://100.119.194.49:8765');
  final _personIdCtrl = TextEditingController(text: 'INF2512001');
  final _datetimeCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController(text: 'NGUYỄN VIẾT THÁI');
  final _rtspCtrl = TextEditingController(text: 'cua_chinh');
  final _regionIdCtrl = TextEditingController(text: '1');

  List<String> _personIdHistory = [];
  List<String> _fullNameHistory = [];

  final List<_LogEntry> _logs = [];
  bool _isSending = false;
  StreamSubscription<dynamic>? _sub;
  WebSocketChannel? _channel;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _startClock();
    _loadHistory();
  }

  void _startClock() {
    _updateDatetime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateDatetime());
  }

  void _updateDatetime() {
    final now = DateTime.now();
    final s = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _datetimeCtrl.text = s;
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _personIdHistory = prefs.getStringList('person_id_history') ?? [];
      _fullNameHistory = prefs.getStringList('full_name_history') ?? [];
    });
  }

  Future<void> _saveToHistory(String prefKey, List<String> current, String value) async {
    if (value.isEmpty) return;
    final updated = [value, ...current.where((e) => e != value)].take(20).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefKey, updated);
    setState(() {
      if (prefKey == 'person_id_history') _personIdHistory = updated;
      if (prefKey == 'full_name_history') _fullNameHistory = updated;
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _serverUrlCtrl.dispose();
    _personIdCtrl.dispose();
    _datetimeCtrl.dispose();
    _fullNameCtrl.dispose();
    _rtspCtrl.dispose();
    _regionIdCtrl.dispose();
    super.dispose();
  }

  void _addLog(String text, {_LogType type = _LogType.info}) {
    setState(() => _logs.add(_LogEntry(text, type)));
  }

  Future<void> _sendCommand() async {
    await _sub?.cancel();
    await _channel?.sink.close();

    final personId = _personIdCtrl.text.trim();
    final fullName = _fullNameCtrl.text.trim();

    await _saveToHistory('person_id_history', _personIdHistory, personId);
    await _saveToHistory('full_name_history', _fullNameHistory, fullName);

    setState(() {
      _logs.clear();
      _isSending = true;
    });

    final payload = {
      'person_id': personId,
      'datetime': _datetimeCtrl.text.trim(),
      'full_name': fullName,
      'rtsp': _rtspCtrl.text.trim(),
      'region_id': _regionIdCtrl.text.trim(),
    };

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrlCtrl.text.trim()));
      await _channel!.ready;

      _channel!.sink.add(jsonEncode(payload));
      _addLog('Đã gửi lệnh, chờ kết quả...', type: _LogType.info);

      _sub = _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;

          if (data['status'] == 'running') {
            _addLog('Server đang chạy lệnh...', type: _LogType.info);
            return;
          }

          final exitCode = data['exit_code'];
          _addLog('Exit code: $exitCode',
              type: exitCode == 0 ? _LogType.success : _LogType.error);

          if (data['stdout'] != null && (data['stdout'] as String).isNotEmpty) {
            _addLog('=== STDOUT ===', type: _LogType.header);
            _addLog(data['stdout'] as String, type: _LogType.stdout);
          }
          if (data['stderr'] != null && (data['stderr'] as String).isNotEmpty) {
            _addLog('=== STDERR ===', type: _LogType.header);
            _addLog(data['stderr'] as String, type: _LogType.error);
          }
          if (data['error'] != null && (data['error'] as String).isNotEmpty) {
            _addLog('=== ERROR ===', type: _LogType.header);
            _addLog(data['error'] as String, type: _LogType.error);
          }

          setState(() => _isSending = false);
          _sub?.cancel();
          _channel?.sink.close();
        },
        onError: (error) {
          _addLog('WebSocket error: $error', type: _LogType.error);
          setState(() => _isSending = false);
        },
        onDone: () {
          if (_isSending) {
            _addLog('Connection closed by server.', type: _LogType.info);
            setState(() => _isSending = false);
          }
        },
      );
    } catch (e) {
      _addLog('Connection failed: $e', type: _LogType.error);
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('WS Command Sender'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildField('Server URL', _serverUrlCtrl),
            const SizedBox(height: 8),
            _buildHistoryField('Person ID', _personIdCtrl, _personIdHistory, 'person_id_history'),
            const SizedBox(height: 8),
            _buildDatetimeField(),
            const SizedBox(height: 8),
            _buildHistoryField('Full Name', _fullNameCtrl, _fullNameHistory, 'full_name_history'),
            const SizedBox(height: 8),
            _buildField('RTSP', _rtspCtrl),
            const SizedBox(height: 8),
            _buildField('Region ID', _regionIdCtrl),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isSending ? null : _sendCommand,
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSending ? 'Đang gửi...' : 'Gửi lệnh'),
            ),
            const SizedBox(height: 16),
            const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(12),
                child: _logs.isEmpty
                    ? const Center(
                        child: Text('Chưa có log.',
                            style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (_, i) {
                          final entry = _logs[i];
                          return Text(
                            entry.text,
                            style: TextStyle(
                              color: entry.color,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _buildDatetimeField() {
    return TextField(
      controller: _datetimeCtrl,
      readOnly: true,
      decoration: const InputDecoration(
        labelText: 'Datetime (thời gian thực)',
        border: OutlineInputBorder(),
        isDense: true,
        prefixIcon: Icon(Icons.access_time),
      ),
    );
  }

  Widget _buildHistoryField(
    String label,
    TextEditingController ctrl,
    List<String> history,
    String prefKey,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (history.isNotEmpty) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Lịch sử',
            icon: const Icon(Icons.history),
            onSelected: (value) => setState(() => ctrl.text = value),
            itemBuilder: (_) => [
              const PopupMenuItem(
                enabled: false,
                child: Text('Lịch sử đã nhập',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
              ...history.map((e) => PopupMenuItem(value: e, child: Text(e))),
              const PopupMenuDivider(),
              PopupMenuItem(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(prefKey);
                  setState(() {
                    if (prefKey == 'person_id_history') _personIdHistory = [];
                    if (prefKey == 'full_name_history') _fullNameHistory = [];
                  });
                },
                child: const Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Xoá lịch sử', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

enum _LogType { info, success, error, stdout, header }

class _LogEntry {
  final String text;
  final _LogType type;

  _LogEntry(this.text, this.type);

  Color get color => switch (type) {
        _LogType.info => Colors.white70,
        _LogType.success => Colors.greenAccent,
        _LogType.error => Colors.redAccent,
        _LogType.stdout => Colors.lightBlueAccent,
        _LogType.header => Colors.yellowAccent,
      };
}
