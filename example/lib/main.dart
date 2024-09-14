// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  FtpServer? ftpServer;
  String serverStatus = 'Server is not running';
  String connectionInfo = 'No connection info';
  String directoryPath = 'No directory chosen';
  bool isLoading = false;
  Isolate? isolate;
  ReceivePort? receivePort;
  int? port;
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _requestPermission();
    }
    _loadDirectory();
  }

  Future<void> _requestPermission() async {
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
  }

  Future<void> _loadDirectory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedDirectory = prefs.getString('serverDirectory');
    if (savedDirectory != null) {
      setState(() {
        directoryPath = savedDirectory;
      });
    }
  }

  Future<String> getIpAddress() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return 'Unknown IP';
  }

  Future<String?> pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('serverDirectory', selectedDirectory);
      setState(() {
        directoryPath = selectedDirectory;
      });
    }
    return selectedDirectory;
  }

  Future<void> toggleServer() async {
    setState(() {
      isLoading = true;
    });

    if (ftpServer == null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? serverDirectory = prefs.getString('serverDirectory');

      if (serverDirectory == null) {
        serverDirectory = await pickDirectory();
        if (serverDirectory != null) {
          await prefs.setString('serverDirectory', serverDirectory);
        } else {
          setState(() {
            isLoading = false;
          });
          return;
        }
      }

      var server = FtpServer(
        port ?? Random().nextInt(65535),
        sharedDirectories: [serverDirectory],
        serverType: ServerType.readAndWrite,
        logFunction: (p0) => print(p0),
      );

      Future serverFuture = server.start();
      ftpServer = server;
      var address = await getIpAddress();

      setState(() {
        serverStatus = 'Server is running';
        connectionInfo =
            'Connect using FTP client:\nftp://$address:${server.port}';
        isLoading = false;
      });

      await serverFuture;
    } else {
      await ftpServer!.stop();
      ftpServer = null;
      setState(() {
        serverStatus = 'Server is not running';
        connectionInfo = 'No connection info';
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    receivePort?.close();
    isolate?.kill(priority: Isolate.immediate);
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
              Text(serverStatus),
              const SizedBox(height: 20),
              Text(connectionInfo),
              const SizedBox(height: 20),
              Text('Directory: $directoryPath'),
              const SizedBox(height: 20),
              isLoading
                  ? const CircularProgressIndicator()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: toggleServer,
                          child: Text(
                            ftpServer == null ? 'Start Server' : 'Stop Server',
                          ),
                        ),
                        const SizedBox(width: 20),
                        ElevatedButton(
                          onPressed: pickDirectory,
                          child: const Text('Pick Directory'),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
