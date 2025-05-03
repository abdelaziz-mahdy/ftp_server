// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:example/network_info_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/server_type.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

// Example usage:
//
// This app demonstrates using the FTP server, which can use either VirtualFileOperations (default) or PhysicalFileOperations.
// For advanced use cases or to learn more about the internal file operation backends, see the README.

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: FtpServerHome(),
    );
  }
}

class FtpServerHome extends StatefulWidget {
  const FtpServerHome({super.key});

  @override
  State<FtpServerHome> createState() => _FtpServerHomeState();
}

class _FtpServerHomeState extends State<FtpServerHome> {
  FtpServer? ftpServer;
  String serverStatus = 'Server is not running';
  String connectionInfo = 'No connection info';
  String directoryPath = 'No directory chosen';
  bool isLoading = false;
  Isolate? isolate;
  ReceivePort? receivePort;
  int? port;
  bool usePhysical = false;
  String get backendWarning => usePhysical
      ? 'Physical (Single Directory): You are sharing one folder as the FTP root. You can add, edit, or delete files and folders directly inside this root.'
      : 'Virtual (Multiple Directories): You are sharing several folders as top-level directories. You cannot add, edit, or delete files directly at the root, only inside the shared folders.';

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

  Future<String?> getIpAddress() async {
    return await NetworkInfoService.getDeviceIpAddress();
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

      final fileOps = usePhysical
          ? PhysicalFileOperations(directoryPath)
          : VirtualFileOperations([directoryPath]);

      var server = FtpServer(
        port ?? Random().nextInt(65535),
        fileOperations: fileOps,
        serverType: ServerType.readAndWrite,
        logFunction: (p0) => print(p0),
        username: null,
        password: null,
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
    final isServerRunning = ftpServer != null;
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Flutter FTP Server'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: [
                        Icon(
                          isServerRunning ? Icons.cloud_done : Icons.cloud_off,
                          color: isServerRunning ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          serverStatus,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isServerRunning ? Colors.green : Colors.red,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isServerRunning)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Connection Info',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SelectableText(
                                  connectionInfo,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy server URL',
                                onPressed: () async {
                                  await Clipboard.setData(ClipboardData(
                                      text: connectionInfo.replaceAll(
                                          'Connect using FTP client:\n', '')));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Server URL copied to clipboard!')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    const Text(
                      'Root Directory',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message:
                          'This is the directory shared by the FTP server.',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder, color: Colors.blueGrey),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                directoryPath,
                                style: const TextStyle(fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_location_alt),
                              tooltip: isServerRunning
                                  ? 'Stop the server to change directory.'
                                  : 'Pick a new directory',
                              onPressed: isServerRunning
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Change Directory'),
                                          content: const Text(
                                              'Are you sure you want to change the root directory?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Change'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        await pickDirectory();
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Backend:'),
                        const SizedBox(width: 12),
                        Tooltip(
                          message:
                              'Virtual: Multiple mapped roots, cannot write to root. Physical: One root, can write/delete at root.',
                          child: Row(
                            children: [
                              const Text('Virtual'),
                              Switch(
                                value: usePhysical,
                                onChanged: isServerRunning
                                    ? null
                                    : (val) {
                                        setState(() {
                                          usePhysical = val;
                                        });
                                      },
                              ),
                              const Text('Physical'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      backendWarning,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 24),
                    isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Tooltip(
                                message: isServerRunning
                                    ? 'Stop the FTP server'
                                    : 'Start the FTP server',
                                child: ElevatedButton.icon(
                                  icon: Icon(isServerRunning
                                      ? Icons.stop
                                      : Icons.play_arrow),
                                  label: Text(isServerRunning
                                      ? 'Stop Server'
                                      : 'Start Server'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isServerRunning
                                        ? Colors.red
                                        : Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 14),
                                  ),
                                  onPressed: () async {
                                    if (isServerRunning) {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Stop Server'),
                                          content: const Text(
                                              'Are you sure you want to stop the server?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Stop'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        await toggleServer();
                                      }
                                    } else {
                                      await toggleServer();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
