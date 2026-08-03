import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;

  Future<String?> pickAndUploadPhoto(String groupId, String uid) async {
    try {
      final image = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1200, imageQuality: 80);
      if (image == null) return null;
      return await _uploadFile(File(image.path), groupId, uid, 'photos', '.jpg');
    } catch (e) {
      print('Error foto: $e');
      return null;
    }
  }

  Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _recordingPath = '${dir.path}/${const Uuid().v4()}.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
          path: _recordingPath!,
        );
        _isRecording = true;
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<String?> stopAndUploadRecording(String groupId, String uid) async {
    try {
      if (!_isRecording) return null;
      final path = await _audioRecorder.stop();
      _isRecording = false;
      if (path == null) return null;
      return await _uploadFile(File(path), groupId, uid, 'audio', '.m4a');
    } catch (e) {
      return null;
    }
  }

  bool get isRecording => _isRecording;

  Future<String> _uploadFile(File file, String groupId, String uid, String folder, String ext) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}$ext';
    final ref = _storage.ref().child('$folder/$groupId/$uid/$fileName');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }
}