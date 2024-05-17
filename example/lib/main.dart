import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  FtpServer? _ftpServer;
  String _serverStatus = 'Server is not running';
  String _connectionInfo = 'No connection info';
  bool _isLoading = false;
  Isolate? _isolate;
  ReceivePort? _receivePort;

  Future<void> _toggleServer() async {
    setState(() {
      _isLoading = true;
    });

    if (_ftpServer == null) {
      var server = FtpServer(21,
          startingDirectory: (await getDownloadsDirectory())!.path,
          allowedDirectories: [(await getDownloadsDirectory())!.path],
          serverType: ServerType.readOnly);
      Future serverFuture = server.start();

      _ftpServer = server;
      var address = InternetAddress
          .anyIPv4; // Modify this to retrieve the correct network interface
      setState(() {
        _serverStatus = 'Server is running';
        _connectionInfo =
            'Connect using IP: ${address.address}, Port: ${_ftpServer!.port}';
        _isLoading = false;
      });
      await serverFuture;
    } else {
      await _ftpServer!.stop();
      _ftpServer = null;
      setState(() {
        _serverStatus = 'Server is not running';
        _connectionInfo = 'No connection info';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter FTP Server'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(_serverStatus),
              const SizedBox(height: 20),
              Text(_connectionInfo),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _toggleServer,
                      child: Text(
                          _ftpServer == null ? 'Start Server' : 'Stop Server'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
