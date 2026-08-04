import 'dart:async';
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
  StreamSubscription? _audioSub;
  String? _playingUrl;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _audioSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingUrl = null);
    });
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final alertsAsync = ref.watch(groupAlertsProvider);

    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Chat del Grupo', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Expanded(
            child: alertsAsync.when(
              data: (alerts) {
                if (alerts.isEmpty) {
                  return const Center(
                    child: Text('No hay mensajes aún', style: TextStyle(color: Colors.white38)),
                  );
                }
                // FIX: reverse:true pone el último mensaje abajo
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: alerts.length,
                  itemBuilder: (ctx, i) => _buildBubble(alerts[i], user),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: \$e', style: const TextStyle(color: Colors.white70))),
            ),
          ),
          // Input cristal abajo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.blue),
                    onPressed: () => _sendPhoto(user),
                  ),
                  GestureDetector(
                    onLongPressStart: (_) => _startRecording(user),
                    onLongPressEnd: (_) => _stopRecording(user),
                    child: Icon(
                      _isRecording ? Icons.stop_circle : Icons.mic,
                      color: _isRecording ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      maxLines: 3,
                      minLines: 1,
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
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(AppAlert alert, AppUser currentUser) {
    final isMine = alert.senderId == currentUser.uid;
    final isSOS = alert.type == 'SOS';
    final time = DateFormat('HH:mm').format(alert.timestamp);
    final senderName = alert.senderName ?? 'Miembro';

    if (isSOS) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withOpacity(0.5)),
              boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 15)],
            ),
            child: Text(
              '🚨 \${alert.payload}',
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      );
    }

    if (alert.type == 'geofence') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Text(
              '📍 \${alert.payload}',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade200),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.blue.withOpacity(0.2)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          border: Border.all(
            color: isMine
                ? Colors.blue.withOpacity(0.3)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FIX: Nombre - (mensaje)
            if (!isMine)
              Text(
                '\$senderName -',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade300,
                ),
              ),
            const SizedBox(height: 3),
            if (alert.type == 'photo') ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: alert.payload,
                  placeholder: (_, __) => const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 50, color: Colors.white54),
                  width: 200,
                  fit: BoxFit.cover,
                ),
              ),
            ] else if (alert.type == 'audio') ...[
              _buildAudioPlayer(alert.payload),
            ] else ...[
              Text(alert.payload, style: const TextStyle(fontSize: 14, color: Colors.white)),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(time, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4))),
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
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
          onPressed: () async {
            if (isPlaying) {
              await _audioPlayer.pause();
              setState(() => _playingUrl = null);
            } else {
              await _audioPlayer.play(UrlSource(url));
              setState(() => _playingUrl = url);
            }
          },
        ),
        const Text('🎤 Audio', style: TextStyle(fontSize: 12, color: Colors.white70)),
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
