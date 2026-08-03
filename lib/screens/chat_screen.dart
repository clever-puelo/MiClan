import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/app_models.dart';
import '../providers/app_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _audioPlayer = AudioPlayer();
  String? _playingUrl;
  bool _isRecording = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final alertsAsync = ref.watch(groupAlertsProvider);

    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Chat del Grupo')),
      body: Column(
        children: [
          Expanded(
            child: alertsAsync.when(
              data: (alerts) {
                if (alerts.isEmpty) {
                  return const Center(child: Text('No hay mensajes aún', style: TextStyle(color: Colors.grey)));
                }
                final reversed = alerts.reversed.toList();
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: reversed.length,
                  itemBuilder: (ctx, i) => _buildBubble(reversed[i], user),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.blue),
                  onPressed: () => _sendPhoto(user),
                  tooltip: 'Enviar foto',
                ),
                GestureDetector(
                  onLongPressStart: (_) => _startRecording(user),
                  onLongPressEnd: (_) => _stopRecording(user),
                  child: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic,
                    color: _isRecording ? Colors.red : Colors.green,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textCtrl,
                    decoration: InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      filled: true, fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    maxLines: 3, minLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: () => _sendText(user),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(AppAlert alert, AppUser currentUser) {
    final isMine = alert.senderId == currentUser.uid;
    final isSOS = alert.type == 'SOS';
    final time = DateFormat('HH:mm').format(alert.timestamp);

    if (isSOS) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade100, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red),
            ),
            child: Text('🚨 ${alert.payload}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    if (alert.type == 'geofence') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text('📍 ${alert.payload}', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
          ),
        ),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12), topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMine ? 12 : 0),
            bottomRight: Radius.circular(isMine ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Text(alert.senderName ?? 'Miembro', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
            const SizedBox(height: 2),
            if (alert.type == 'photo') ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: alert.payload,
                  placeholder: (_, __) => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 50),
                  width: 200, fit: BoxFit.cover,
                ),
              ),
            ] else if (alert.type == 'audio') ...[
              _buildAudioPlayer(alert.payload),
            ] else ...[
              Text(alert.payload, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(time, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlayer(String url) {
    final isPlaying = _playingUrl == url;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: () async {
            if (isPlaying) {
              await _audioPlayer.pause();
              setState(() => _playingUrl = null);
            } else {
              await _audioPlayer.play(UrlSource(url));
              setState(() => _playingUrl = url);
              _audioPlayer.onPlayerComplete.listen((_) {
                if (mounted) setState(() => _playingUrl = null);
              });
            }
          },
        ),
        const Text('🎤 Audio', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  void _sendText(AppUser user) {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    ref.read(firestoreServiceProvider).sendAlert(user, 'all', 'quick_message', text);
    _textCtrl.clear();
  }

  Future<void> _sendPhoto(AppUser user) async {
    if (user.groupId == null) return;
    final url = await ref.read(storageServiceProvider).pickAndUploadPhoto(user.groupId!, user.uid);
    if (url != null) {
      ref.read(firestoreServiceProvider).sendAlert(user, 'all', 'photo', url);
    }
  }

  Future<void> _startRecording(AppUser user) async {
    final started = await ref.read(storageServiceProvider).startRecording();
    if (started) {
      setState(() => _isRecording = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎤 Grabando... suelta para enviar'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _stopRecording(AppUser user) async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);
    if (user.groupId == null) return;
    final url = await ref.read(storageServiceProvider).stopAndUploadRecording(user.groupId!, user.uid);
    if (url != null) {
      ref.read(firestoreServiceProvider).sendAlert(user, 'all', 'audio', url);
    }
  }
}