import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BackupService {
  /// A portable UTF-8 JSON backup can be exported and imported without a server.
  Future<String?> exportFile(String data) async {
    final filename='event_reminder_${DateTime.now().toIso8601String().substring(0,10)}.json';
    final bytes=Uint8List.fromList(utf8.encode(data));
    final path=await FilePicker.platform.saveFile(
      dialogTitle:'Зберегти резервну копію',
      fileName:filename, type:FileType.custom, allowedExtensions:['json'],bytes:bytes,
    );
    // On desktop saveFile returns a path and may not write the bytes itself.
    // On Android/iOS modern file_picker saves them when bytes is provided.
    if(path!=null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await File(path).writeAsBytes(bytes,flush:true);
    }
    if(path!=null) return path;
    // Cancel means no backup should be created or claimed.
    return null;
  }
  Future<String?> importFile() async {
    final result=await FilePicker.platform.pickFiles(type:FileType.custom,
      allowedExtensions:['json'],withData:true);
    if(result==null || result.files.isEmpty) return null;
    final file=result.files.single;
    if(file.bytes!=null) return utf8.decode(file.bytes!);
    if(file.path!=null) return File(file.path!).readAsString();
    throw const FormatException('Не вдалося прочитати резервну копію');
  }
  Future<String> localDatabaseDirectory() async {
    final dir=await getApplicationSupportDirectory();
    return p.join(dir.path,'event_reminder.sqlite');
  }
}
