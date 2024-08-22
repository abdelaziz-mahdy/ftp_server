import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PhysicalFileOperations', () {
    late Directory tempDir;
    late PhysicalFileOperations fileOps;

    setUp(() {
      tempDir =
          Directory.systemTemp.createTempSync('physical_file_operations_test');
      fileOps = PhysicalFileOperations(tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('resolvePath with relative path', () {
      final resolvedPath = fileOps.resolvePath('some/path');
      expect(resolvedPath, equals(p.join(tempDir.path, 'some', 'path')));
    });

    test('resolvePath with absolute path', () {
      final resolvedPath =
          fileOps.resolvePath(p.join(tempDir.path, 'some', 'path'));
      expect(resolvedPath, equals(p.join(tempDir.path, 'some', 'path')));
    });

    test('resolvePath with special characters', () {
      final resolvedPath =
          fileOps.resolvePath('some/path with spaces and !@#\$%^&*()');
      expect(
          resolvedPath,
          equals(p.join(
              tempDir.path, 'some', 'path with spaces and !@#\$%^&*()')));
    });

    test('exists returns true for existing file', () {
      final file = File(p.join(tempDir.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      expect(fileOps.exists('test_file.txt'), isTrue);
    });

    test('exists returns false for non-existing file', () {
      expect(fileOps.exists('non_existing_file.txt'), isFalse);
    });

    test('createDirectory creates directory', () async {
      await fileOps.createDirectory('new_directory');
      final dir = Directory(p.join(tempDir.path, 'new_directory'));
      expect(dir.existsSync(), isTrue);
    });

    test('createDirectory with special characters', () async {
      await fileOps.createDirectory('new_directory_with_!@#\$%^&*()');
      final dir =
          Directory(p.join(tempDir.path, 'new_directory_with_!@#\$%^&*()'));
      expect(dir.existsSync(), isTrue);
    });

    test('createDirectory with nested directories', () async {
      await fileOps.createDirectory('new_directory/sub_directory');
      final dir =
          Directory(p.join(tempDir.path, 'new_directory', 'sub_directory'));
      expect(dir.existsSync(), isTrue);
    });

    test('deleteFile deletes file', () async {
      final file = File(p.join(tempDir.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      await fileOps.deleteFile('test_file.txt');
      expect(file.existsSync(), isFalse);
    });

    test('deleteFile with non-existing file', () async {
      expect(() async => await fileOps.deleteFile('non_existing_file.txt'),
          throwsA(isA<FileSystemException>()));
    });

    test('deleteDirectory deletes directory', () async {
      final dir = Directory(p.join(tempDir.path, 'test_dir'));
      dir.createSync();
      await fileOps.deleteDirectory('test_dir');
      expect(dir.existsSync(), isFalse);
    });

    test('deleteDirectory with files inside', () async {
      final dir = Directory(p.join(tempDir.path, 'test_dir'));
      dir.createSync();
      final file = File(p.join(dir.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      await fileOps.deleteDirectory('test_dir');
      expect(dir.existsSync(), isFalse);
    });

    test('getFile returns correct file', () async {
      final file = File(p.join(tempDir.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final fetchedFile = await fileOps.getFile('test_file.txt');
      expect(fetchedFile.path, equals(file.path));
    });

    test('listDirectory lists files and directories', () async {
      final file = File(p.join(tempDir.path, 'test_file.txt'));
      final dir = Directory(p.join(tempDir.path, 'test_dir'));
      file.writeAsStringSync('Hello, World!');
      dir.createSync();

      final entities = await fileOps.listDirectory('/');
      expect(entities.length, equals(2));
      expect(entities.map((e) => p.basename(e.path)),
          containsAll(['test_file.txt', 'test_dir']));
    });

    test('listDirectory with hidden files', () async {
      final file = File(p.join(tempDir.path, '.hidden_file.txt'));
      file.writeAsStringSync('Hello, Hidden World!');
      final entities = await fileOps.listDirectory('/');
      expect(entities.map((e) => p.basename(e.path)),
          contains('.hidden_file.txt'));
    });

    test('fileSize returns correct size', () async {
      final file = File(p.join(tempDir.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final size = await fileOps.fileSize('test_file.txt');
      expect(size, equals(13));
    });

    test('fileSize for non-existing file', () async {
      expect(() async => await fileOps.fileSize('non_existing_file.txt'),
          throwsA(isA<FileSystemException>()));
    });

    test('changeDirectory using relative path', () async {
      await fileOps.createDirectory('subdir');
      fileOps.changeDirectory('subdir');
      expect(fileOps.getCurrentDirectory(),
          equals(p.join(tempDir.path, 'subdir')));
    });

    test('changeDirectory using absolute path', () async {
      await fileOps.createDirectory('subdir');
      fileOps.changeDirectory(p.join(tempDir.path, 'subdir'));
      expect(fileOps.getCurrentDirectory(),
          equals(p.join(tempDir.path, 'subdir')));
    });

    test('changeToParentDirectory moves to parent directory', () async {
      await fileOps.createDirectory('subdir');
      fileOps.changeDirectory('subdir');
      fileOps.changeToParentDirectory();
      expect(fileOps.getCurrentDirectory(), equals(tempDir.path));
    });

    test('writeFile writes data to file', () async {
      final data = 'Hello, World!'.codeUnits;
      await fileOps.writeFile('test_file.txt', data);
      final file = File(p.join(tempDir.path, 'test_file.txt'));
      expect(file.readAsStringSync(), equals('Hello, World!'));
    });

    test('readFile reads data from file', () async {
      final file = File(p.join(tempDir.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final data = await fileOps.readFile('test_file.txt');
      expect(String.fromCharCodes(data), equals('Hello, World!'));
    });
  });

  group('VirtualFileOperations', () {
    late Directory tempDir1;
    late Directory tempDir2;
    late VirtualFileOperations fileOps;

    setUp(() {
      tempDir1 =
          Directory.systemTemp.createTempSync('virtual_file_operations_test1');
      tempDir2 =
          Directory.systemTemp.createTempSync('virtual_file_operations_test2');
      fileOps = VirtualFileOperations([tempDir1.path, tempDir2.path]);
    });

    tearDown(() {
      tempDir1.deleteSync(recursive: true);
      tempDir2.deleteSync(recursive: true);
    });

    test('resolvePath with relative path', () {
      fileOps.changeDirectory('/${p.basename(tempDir1.path)}');
      final resolvedPath = fileOps.resolvePath('some/path');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'some', 'path')));
    });

    test('resolvePath with absolute path', () {
      final resolvedPath = fileOps
          .resolvePath('/${p.basename(tempDir1.path)}/some/absolute/path');
      expect(resolvedPath, equals(p.join(tempDir1.path, 'some/absolute/path')));
    });

    test('resolvePath with special characters in path', () {
      final resolvedPath = fileOps.resolvePath(
          '/${p.basename(tempDir1.path)}/some/special!@#\$%^&*()/path');
      expect(resolvedPath,
          equals(p.join(tempDir1.path, 'some/special!@#\$%^&*()/path')));
    });

    test('exists returns true for existing file', () {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      expect(fileOps.exists(p.join(p.basename(tempDir1.path), 'test_file.txt')),
          isTrue);
    });

    test('exists returns false for non-existing file', () {
      expect(
          fileOps.exists(
              p.join(p.basename(tempDir1.path), 'non_existing_file.txt')),
          isFalse);
    });

    test('createDirectory creates directory', () async {
      await fileOps
          .createDirectory(p.join(p.basename(tempDir1.path), 'new_directory'));
      final dir = Directory(p.join(tempDir1.path, 'new_directory'));
      expect(dir.existsSync(), isTrue);
    });

    test('createDirectory with special characters', () async {
      await fileOps.createDirectory(
          p.join(p.basename(tempDir1.path), 'new_directory_with_!@#\$%^&*()'));
      final dir =
          Directory(p.join(tempDir1.path, 'new_directory_with_!@#\$%^&*()'));
      expect(dir.existsSync(), isTrue);
    });

    test('deleteFile deletes file', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      await fileOps
          .deleteFile(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(file.existsSync(), isFalse);
    });
    test('deleteFile with non-existing file', () async {
      expect(() async => await fileOps.deleteFile('non_existing_file.txt'),
          throwsA(isA<FileSystemException>()));
    });
    test('deleteDirectory deletes directory', () async {
      final dir = Directory(p.join(tempDir1.path, 'test_dir'));
      dir.createSync();
      await fileOps
          .deleteDirectory(p.join(p.basename(tempDir1.path), 'test_dir'));
      expect(dir.existsSync(), isFalse);
    });

    test('getFile returns correct file', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final fetchedFile = await fileOps
          .getFile(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(fetchedFile.path, equals(file.path));
    });

    test('listDirectory lists files and directories', () async {
      final file1 = File(p.join(tempDir1.path, 'test_file.txt'));
      final file2 = File(p.join(tempDir1.path, 'test_file2.txt'));
      final dir = Directory(p.join(tempDir1.path, 'test_dir'));
      file1.writeAsStringSync('Hello, World!');
      file2.writeAsStringSync('Hello, FTP!');
      dir.createSync();
      final entities =
          await fileOps.listDirectory('/${p.basename(tempDir1.path)}');
      expect(entities.length, equals(3));
      expect(entities.map((e) => p.basename(e.path)),
          containsAll(['test_file.txt', 'test_file2.txt', 'test_dir']));
    });

    test('fileSize returns correct size', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final size = await fileOps
          .fileSize(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(size, equals(13));
    });

    test('changeDirectory using relative path', () async {
      String subDirPath = p.join(p.basename(tempDir1.path), 'subdir');
      await fileOps.createDirectory(subDirPath);
      fileOps.changeDirectory(subDirPath);
      expect(fileOps.getCurrentDirectory(), equals(p.join('/', subDirPath)));
    });

    test('changeDirectory using absolute path', () async {
      String subDirPath = p.join('/', p.basename(tempDir1.path), 'subdir');
      await fileOps.createDirectory(subDirPath);
      fileOps.changeDirectory(subDirPath);
      expect(fileOps.getCurrentDirectory(), equals(p.join('/', subDirPath)));
    });

    test('changeToParentDirectory moves to parent directory', () async {
      String subDirPath = p.join('/', p.basename(tempDir1.path), 'subdir');
      await fileOps.createDirectory(subDirPath);
      fileOps.changeDirectory(subDirPath);
      fileOps.changeToParentDirectory();
      expect(fileOps.getCurrentDirectory(),
          equals('/${p.basename(tempDir1.path)}'));
    });

    test('writeFile writes data to file', () async {
      final data = 'Hello, World!'.codeUnits;
      await fileOps.writeFile(
          p.join(p.basename(tempDir1.path), 'test_file.txt'), data);
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      expect(file.readAsStringSync(), equals('Hello, World!'));
    });

    test('readFile reads data from file', () async {
      final file = File(p.join(tempDir1.path, 'test_file.txt'));
      file.writeAsStringSync('Hello, World!');
      final data = await fileOps
          .readFile(p.join(p.basename(tempDir1.path), 'test_file.txt'));
      expect(String.fromCharCodes(data), equals('Hello, World!'));
    });
  });
}
