import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api_config.dart';

/// Icône exacte de la barre latérale (compacte et épurée comme sur Claude).
class _SidebarToggleIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _SidebarToggleIcon({this.color = Colors.white, this.size = 19});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: size,
          height: size * 0.80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3.5),
            border: Border.all(color: color, width: 1.4),
          ),
          child: Row(
            children: [
              const Expanded(flex: 5, child: SizedBox()),
              Container(width: 1.4, color: color),
              const Expanded(flex: 4, child: SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modèle d'une conversation (session de chat).
class _Conversation {
  final String id;
  final String title;
  final DateTime createdAt;

  _Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
  });
}

/// Modèle d'un message dans le chat.
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  final String? sourceLine;
  final List<String> images;

  _ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.sourceLine,
    this.images = const [],
  });
}

class _BotReply {
  final String text;
  final String? sourceLine;
  final List<String> images;

  const _BotReply({
    required this.text,
    this.sourceLine,
    this.images = const [],
  });
}

/// Page de chat : Couleurs officielles WhatsApp Dark Mode + Sidebar Claude.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _botTyping = false;
  bool _loadingMessages = false;
  bool _showSidebar = true;
  bool _isDarkMode =
      true; // Actif par défaut sur le thème sombre officiel WhatsApp
  bool _speechAvailable = false;
  bool _isListening = false;
  double _sidebarWidth = 260.0;

  final stt.SpeechToText _speech = stt.SpeechToText();

  List<_Conversation> _conversations = [];
  String? _currentConversationId;

  final List<_ChatMessage> _messages = [];

  static const String _defaultWelcomeText =
      'Bonjour ! 👋 Je suis le Chatbot officiel de l\'EMSI.\nComment puis-je vous aider aujourd\'hui ?';

  @override
  void initState() {
    super.initState();
    _resetToWelcomeMessage();
    _loadConversations();
    _initialiserReconnaissanceVocale();
  }

  @override
  void dispose() {
    _speech.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initialiserReconnaissanceVocale() async {
    final disponible = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    if (!mounted) return;

    setState(() => _speechAvailable = disponible);
    if (!disponible) {
      _showSpeechMessage(
        'La reconnaissance vocale n’est pas disponible ou la permission est refusée.',
      );
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'listening') {
      setState(() => _isListening = true);
    } else if (status == 'done' || status == 'notListening') {
      setState(() => _isListening = false);
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() => _isListening = false);
    _showSpeechMessage(
      'Reconnaissance vocale indisponible : ${error.errorMsg}',
    );
  }

  void _showSpeechMessage(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    });
  }

  Future<void> _toggleSpeech() async {
    if (!_speechAvailable) {
      _showSpeechMessage(
        'La reconnaissance vocale n’est pas disponible sur cet appareil.',
      );
      return;
    }

    if (_speech.isListening || _isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    try {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _controller.text = result.recognizedWords;
            _controller.selection = TextSelection.collapsed(
              offset: _controller.text.length,
            );
          });
        },
        localeId: 'fr_FR',
        partialResults: true,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
      _showSpeechMessage('Impossible de démarrer la reconnaissance vocale.');
    }
  }

  void _resetToWelcomeMessage() {
    _messages.clear();
    _messages.add(
      _ChatMessage(
        text: _defaultWelcomeText,
        isUser: false,
        time: DateTime.now(),
      ),
    );
  }

  // ==========================================
  // Vert Officiel Unique EMSI (#134D37)
  // Appliqué identiquement sur :
  // 1. Le haut ruban (AppBar)
  // 2. La partie verte de la sidebar (+ Nouvelle discussion)
  // 3. Les bulles de message utilisateur
  // En Dark Mode ET en Light Mode !
  // ==========================================
  static const Color _signatureGreen = Color(0xFF134D37);

  // Thème Sombre
  static const Color _waChatDark = Color(
    0xFF191919,
  ); // Fond de discussion sombre
  static const Color _waSidebarDark = Color(
    0xFF202020,
  ); // Sidebar gauche sombre
  static const Color _waBotBubbleDark = Color(
    0xFF222222,
  ); // Bulle reçue gris anthracite WhatsApp
  static const Color _waInputBarDark = Color(
    0xFF1E1E1E,
  ); // Barre de saisie en bas
  static const Color _waInputFieldDark = Color(0xFF2A2A2A); // Champ de texte
  static const Color _waAccentGreen = Color(
    0xFF23C768,
  ); // Vert vibrant WhatsApp (icônes)
  static const Color _waTextLight = Color(0xFFFFFFFF); // Texte blanc principal
  static const Color _waTextMuted = Color(
    0xFF8696A0,
  ); // Horodatage & textes secondaires
  static const Color _waBorderDark = Color(
    0xFF282828,
  ); // Lignes de séparation discrètes
  static const Color _waBlueCheck = Color(
    0xFF53BDEB,
  ); // Double coches bleues officielles

  // Thème Clair
  static const Color _waChatLight = Color(
    0xFFFAF9F6,
  ); // Fond de discussion clair épuré
  static const Color _waSidebarLight = Color(
    0xFFF3EFE6,
  ); // Sidebar en beige doux élégant
  static const Color _waBotBubbleLight = Color(
    0xFFFFFFFF,
  ); // Bulle réponse blanche
  static const Color _waInputBarLight = Color(
    0xFFF3EFE6,
  ); // Barre de saisie beige
  static const Color _waInputFieldLight = Color(
    0xFFFFFFFF,
  ); // Champ de texte blanc
  static const Color _waBorderLight = Color(
    0xFFE2DDD2,
  ); // Ligne séparatrice beige discrète

  Color get _chatBg => _isDarkMode ? _waChatDark : _waChatLight;
  Color get _sidebarBg => _isDarkMode ? _waSidebarDark : _waSidebarLight;
  Color get _headerBg =>
      _signatureGreen; // Même vert en haut ruban (Dark et Light)
  Color get _userBubbleBg =>
      _signatureGreen; // Même vert pour messages (Dark et Light)
  Color get _userTextColor => Colors.white;
  Color get _botBubbleBg => _isDarkMode ? _waBotBubbleDark : _waBotBubbleLight;
  Color get _botTextColor =>
      _isDarkMode ? _waTextLight : const Color(0xFF111B21);
  Color get _inputBarBg => _isDarkMode ? _waInputBarDark : _waInputBarLight;
  Color get _inputFieldBg =>
      _isDarkMode ? _waInputFieldDark : _waInputFieldLight;
  Color get _inputTextColor =>
      _isDarkMode ? _waTextLight : const Color(0xFF111B21);
  Color get _border => _isDarkMode ? _waBorderDark : _waBorderLight;
  Color get _timeTextColor =>
      _isDarkMode ? _waTextMuted : const Color(0xFF667781);

  // ==========================================
  // Gestion Supabase : Conversations & Messages
  // ==========================================

  Future<void> _loadConversations() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final dynamic response = await Supabase.instance.client
          .from('conversations')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;

      if (response is List && response.isNotEmpty) {
        final List<_Conversation> loaded = [];
        for (final row in response) {
          if (row is Map) {
            loaded.add(
              _Conversation(
                id: (row['id'] ?? '').toString(),
                title: (row['title'] ?? 'Discussion').toString(),
                createdAt:
                    DateTime.tryParse(row['created_at']?.toString() ?? '')
                        ?.toLocal() ??
                    DateTime.now(),
              ),
            );
          }
        }

        setState(() {
          _conversations = loaded;
        });

        if (loaded.isNotEmpty) {
          _selectConversation(loaded.first.id);
        }
      } else {
        setState(() {
          _conversations = [];
        });
      }
    } catch (e) {
      debugPrint('Info chargement conversations : $e');
      if (mounted) setState(() => _conversations = []);
    }
  }

  Future<void> _selectConversation(String conversationId) async {
    if (_currentConversationId == conversationId && _messages.length > 1) {
      return;
    }

    setState(() {
      _currentConversationId = conversationId;
      _loadingMessages = true;
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingMessages = false);
      return;
    }

    try {
      final dynamic response = await Supabase.instance.client
          .from('chat_messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);

      if (!mounted) return;

      if (response is List && response.isNotEmpty) {
        final List<_ChatMessage> loadedMessages = [];
        for (final row in response) {
          if (row is Map) {
            final rawImages = row['images'];
            final List<String> imgs = rawImages is List
                ? rawImages.map((e) => e.toString()).toList()
                : const [];

            loadedMessages.add(
              _ChatMessage(
                text: (row['text'] ?? '').toString(),
                isUser: row['is_user'] == true,
                time:
                    DateTime.tryParse(row['created_at']?.toString() ?? '')
                        ?.toLocal() ??
                    DateTime.now(),
                sourceLine: row['source_line']?.toString(),
                images: imgs,
              ),
            );
          }
        }

        setState(() {
          _messages.clear();
          _messages.addAll(loadedMessages);
          _loadingMessages = false;
        });
        _scrollToBottom();
        return;
      }
    } catch (e) {
      debugPrint('Erreur chargement messages : $e');
    }

    if (mounted) {
      setState(() {
        _resetToWelcomeMessage();
        _loadingMessages = false;
      });
    }
  }

  void _startNewChat() {
    setState(() {
      _currentConversationId = null;
      _resetToWelcomeMessage();
    });
  }

  Future<String?> _getOrCreateConversation(String firstQuestion) async {
    if (_currentConversationId != null) return _currentConversationId;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    final trimmed = firstQuestion.trim();
    final title = trimmed.length > 32
        ? '${trimmed.substring(0, 32)}...'
        : trimmed;

    try {
      final res = await Supabase.instance.client
          .from('conversations')
          .insert({
            'user_id': user.id,
            'title': title.isEmpty ? 'Nouvelle discussion' : title,
          })
          .select()
          .single();

      final newConvId = (res['id'] ?? '').toString();
      final newConv = _Conversation(
        id: newConvId,
        title: (res['title'] ?? title).toString(),
        createdAt: DateTime.now(),
      );

      setState(() {
        _currentConversationId = newConvId;
        _conversations.insert(0, newConv);
      });

      return newConvId;
    } catch (e) {
      debugPrint('Erreur création conversation : $e');
      return null;
    }
  }

  Future<void> _saveMessageToSupabase({
    required String text,
    required bool isUser,
    required String? conversationId,
    String? sourceLine,
    List<String> images = const [],
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final payload = <String, dynamic>{
        'user_id': user.id,
        'text': text,
        'is_user': isUser,
        'source_line': sourceLine,
        'images': images,
      };

      if (conversationId != null) {
        payload['conversation_id'] = conversationId;
      }

      await Supabase.instance.client.from('chat_messages').insert(payload);
    } catch (e) {
      debugPrint('Erreur sauvegarde message : $e');
    }
  }

  Future<void> _deleteConversation(String conversationId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('conversations')
            .delete()
            .eq('id', conversationId);
      } catch (e) {
        debugPrint('Erreur suppression conversation: $e');
      }
    }

    setState(() {
      _conversations.removeWhere((c) => c.id == conversationId);
      if (_currentConversationId == conversationId) {
        if (_conversations.isNotEmpty) {
          _selectConversation(_conversations.first.id);
        } else {
          _startNewChat();
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Discussion supprimée.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ==========================================
  // Logique du chatbot EMSI (Fallback hors-ligne)
  // ==========================================

  String _getBotResponse(String input) {
    final msg = input.toLowerCase().trim();

    if (msg.contains('bonjour') ||
        msg.contains('salut') ||
        msg.contains('bonsoir') ||
        msg.contains('hello') ||
        msg.contains('salam')) {
      return 'Bonjour ! 😊 Je suis là pour répondre à toutes vos questions sur l\'EMSI.';
    }
    if (msg.contains('inscription') ||
        msg.contains('inscrire') ||
        msg.contains('candidature')) {
      return 'Pour vous inscrire à l\'EMSI :\n'
          '1️⃣ Visitez www.emsi.ma\n'
          '2️⃣ Rubrique "Admissions"\n'
          '3️⃣ Remplissez le formulaire en ligne\n\n'
          'Vous pouvez aussi contacter l\'administration. 📞';
    }
    if (msg.contains('filière') ||
        msg.contains('formation') ||
        msg.contains('spécialité') ||
        msg.contains('programme')) {
      return 'L\'EMSI propose plusieurs filières d\'excellence 🎓 :\n'
          '• Ingénierie Informatique et Réseaux\n'
          '• Génie Civil\n'
          '• Génie Électrique & Systèmes Embarqués\n'
          '• Ingénierie Financière & Audit\n\n'
          'Pour plus de détails : www.emsi.ma';
    }

    return 'Je n\'ai pas bien compris votre question. 🤔\n'
        'Vous pouvez me poser des questions sur :\n'
        '• Les campus EMSI\n'
        '• Les filières et diplômes\n'
        '• Les modalités d\'inscription\n'
        '• Les stages et débouchés';
  }

  String? _formatSources(dynamic rawSources) {
    if (rawSources is! List || rawSources.isEmpty) return null;

    final pagesBySource = <String, List<String>>{};
    for (final rawSource in rawSources) {
      if (rawSource is! Map || rawSource['type'] != 'text') continue;

      final source = rawSource['source']?.toString();
      final page = rawSource['page']?.toString();
      if (source == null || source.isEmpty || page == null || page.isEmpty) {
        continue;
      }

      final pages = pagesBySource.putIfAbsent(source, () => <String>[]);
      if (!pages.contains(page)) pages.add(page);
    }

    if (pagesBySource.isEmpty) return null;
    final sources = pagesBySource.entries
        .map((entry) => '${entry.key}, p. ${entry.value.join(', ')}')
        .join(' ; ');
    return 'Source : $sources';
  }

  List<String> _extractImages(dynamic rawImages) {
    if (rawImages is! List || rawImages.isEmpty) return const [];

    return rawImages
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .take(2)
        .toList();
  }

  Future<_BotReply> _askServer(String question) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/chat'),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: utf8.encode(jsonEncode({'question': question})),
          )
          .timeout(const Duration(seconds: 90));

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final answer = decoded is Map ? decoded['answer'] : null;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          answer is! String ||
          answer.contains('Le service Groq est indisponible') ||
          answer.contains('Le service de recherche Qdrant est indisponible')) {
        throw const FormatException('Réponse API invalide.');
      }

      return _BotReply(
        text: answer,
        sourceLine: _formatSources(decoded['sources']),
        images: _extractImages(decoded['images']),
      );
    } catch (_) {
      // Ne plus faire semblant de répondre : une vraie réponse d'erreur
      // permet de voir que le serveur est en cause, pas la question.
      return _BotReply(
        text: 'Le serveur ne répond pas pour le moment. '
            'Vérifiez votre connexion et réessayez dans un instant.',
      );
    }
  }

  String _imageUrl(String path) {
    return '$baseUrl${path.startsWith('/') ? path : '/$path'}';
  }

  // ==========================================
  // Affichage d'images avec zoom plein écran
  // ==========================================

  Widget _buildRemoteImages(List<String> images) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: images.take(2).map((path) {
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(16),
                  child: Stack(
                    alignment: Alignment.topRight,
                    children: [
                      Center(
                        child: InteractiveViewer(
                          panEnabled: true,
                          minScale: 0.8,
                          maxScale: 4.0,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              _imageUrl(path),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: CircleAvatar(
                            backgroundColor: Colors.black.withOpacity(0.6),
                            radius: 18,
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _imageUrl(path),
                width: 220,
                height: 140,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return SizedBox(
                    width: 220,
                    height: 140,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _waAccentGreen,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 220,
                    height: 80,
                    color: Colors.black12,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(8),
                    child: const Text('Image indisponible'),
                  );
                },
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ==========================================
  // Envoi d'un message
  // ==========================================

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        _ChatMessage(text: text, isUser: true, time: DateTime.now()),
      );
      _controller.clear();
      _botTyping = true;
    });
    _scrollToBottom();

    final convId = await _getOrCreateConversation(text);

    _saveMessageToSupabase(
      text: text,
      isUser: true,
      conversationId: convId,
      sourceLine: null,
      images: const [],
    );

    final reply = await _askServer(text);
    if (!mounted) return;

    setState(() {
      _botTyping = false;
      _messages.add(
        _ChatMessage(
          text: reply.text,
          isUser: false,
          time: DateTime.now(),
          sourceLine: reply.sourceLine,
          images: reply.images,
        ),
      );
    });
    _scrollToBottom();

    _saveMessageToSupabase(
      text: reply.text,
      isUser: false,
      conversationId: convId,
      sourceLine: reply.sourceLine,
      images: reply.images,
    );
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ==========================================
  // Bulles de messages Style WhatsApp Officiel
  // ==========================================

  Widget _buildBubble(_ChatMessage message) {
    final isUser = message.isUser;
    final displayedText = isUser
        ? message.text
        : message.text.replaceAll('**', '');
    final timeStr =
        '${message.time.hour.toString().padLeft(2, '0')}:${message.time.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isUser ? 64 : 12,
          right: isUser ? 12 : 64,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isUser ? _userBubbleBg : _botBubbleBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEmsiLogo(size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'EMSI Chatbot',
                    style: TextStyle(
                      color: _isDarkMode ? _waAccentGreen : _signatureGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            SelectableText(
              displayedText,
              style: TextStyle(
                color: isUser ? _userTextColor : _botTextColor,
                fontSize: 15,
                height: 1.38,
              ),
            ),
            if (!isUser && message.sourceLine != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                message.sourceLine!,
                style: TextStyle(
                  color: _timeTextColor,
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
            if (!isUser && message.images.isNotEmpty)
              _buildRemoteImages(message.images),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    color: isUser ? Colors.white70 : _timeTextColor,
                    fontSize: 11,
                  ),
                ),
                if (!isUser) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: displayedText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Texte copié dans le presse-papier !'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Icon(
                      Icons.copy_rounded,
                      size: 13,
                      color: _timeTextColor,
                    ),
                  ),
                ],
                if (isUser) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.done_all,
                    size: 15,
                    color: _waBlueCheck, // Double coches bleues WhatsApp
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _botBubbleBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(0),
            const SizedBox(width: 4),
            _dot(150),
            const SizedBox(width: 4),
            _dot(300),
          ],
        ),
      ),
    );
  }

  Widget _dot(int delayMs) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      builder: (_, v, __) => Opacity(
        opacity: (v * 2 - 1).abs().clamp(0.3, 1.0),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: _waAccentGreen,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // Barre latérale gauche (Style WhatsApp Desktop / Claude)
  // ==========================================

  Widget _buildSidebar() {
    final hasConversations = _conversations.isNotEmpty;

    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: _sidebarBg,
        border: Border(right: BorderSide(color: _border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête Sidebar : Titre simple et épuré (icône toggle uniquement dans l'AppBar à côté du logo)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'EMSI Chat',
              style: TextStyle(
                color: _isDarkMode ? _waTextLight : const Color(0xFF111B21),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),

          // Bouton "+ Nouvelle discussion" (Même vert officiel que les bulles de messages)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _startNewChat,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _userBubbleBg, // Même vert foncé élégant que la bulle de message
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isDarkMode
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.06),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.add, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Nouvelle discussion',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Label Section "RÉCENT"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text(
              'RÉCENT',
              style: TextStyle(
                color: _timeTextColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),

          // Liste des discussions passées
          Expanded(
            child: !hasConversations
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Aucune discussion passée',
                        style: TextStyle(color: _timeTextColor, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 6,
                    ),
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      final isSelected = conv.id == _currentConversationId;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (_isDarkMode
                                    ? const Color(0xFF2A3942)
                                    : const Color(0xFFE5DEC9))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -3),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          leading: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _userBubbleBg
                                  : _timeTextColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            conv.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isDarkMode
                                  ? _waTextLight
                                  : const Color(0xFF111B21),
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 13.5,
                            ),
                          ),
                          trailing: isSelected
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: _timeTextColor,
                                  ),
                                  tooltip: 'Supprimer',
                                  onPressed: () => _deleteConversation(conv.id),
                                )
                              : null,
                          onTap: () => _selectConversation(conv.id),
                        ),
                      );
                    },
                  ),
          ),

          // Profil utilisateur en bas de la sidebar
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _waAccentGreen.withOpacity(0.2),
                  child: const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: _waAccentGreen,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Supabase.instance.client.auth.currentUser?.email ??
                        'Étudiant EMSI',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _isDarkMode
                          ? _waTextLight
                          : const Color(0xFF111B21),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Logo officiel EMSI Chatbot (chargement fiable Web & Mobile)
  Widget _buildEmsiLogo({double size = 38}) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.network(
          'emsi_logo.jpg',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset(
              'assets/images/emsi_logo.jpg',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Image.network(
                '/emsi_logo.jpg',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.white,
                  child: Center(
                    child: Text(
                      'EMSI',
                      style: TextStyle(
                        color: _signatureGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: size * 0.28,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Poignée pour redimensionner la sidebar en glissant la souris
  Widget _buildResizeHandle() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) {
          setState(() {
            _sidebarWidth = (_sidebarWidth + details.delta.dx).clamp(
              200.0,
              480.0,
            );
          });
        },
        child: Container(
          width: 5,
          color: _sidebarBg,
          child: Center(child: Container(width: 1, color: _border)),
        ),
      ),
    );
  }

  // ==========================================
  // Construction de l'interface principale
  // ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chatBg,
      // AppBar EMSI avec le vert officiel en haut ruban
      appBar: AppBar(
        backgroundColor: _headerBg,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        shape: Border(bottom: BorderSide(color: _border, width: 1)),
        leading: IconButton(
          icon: const _SidebarToggleIcon(color: Colors.white, size: 19),
          tooltip: _showSidebar
              ? 'Masquer la barre latérale'
              : 'Afficher la barre latérale',
          onPressed: () => setState(() => _showSidebar = !_showSidebar),
        ),
        title: Row(
          children: [
            _buildEmsiLogo(size: 38),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EMSI Chatbot',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _currentConversationId == null
                      ? 'En ligne'
                      : 'Discussion active',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isDarkMode
                  ? Icons.wb_sunny_outlined
                  : Icons.nightlight_round_outlined,
              color: Colors.white,
              size: 20,
            ),
            tooltip: _isDarkMode
                ? 'Passer en mode clair'
                : 'Passer en mode sombre',
            onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: Colors.white),
            tooltip: 'Nouvelle discussion',
            onPressed: _startNewChat,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Row(
        children: [
          // Barre latérale gauche pliable & redimensionnable
          if (_showSidebar) ...[_buildSidebar(), _buildResizeHandle()],

          // Zone principale de chat WhatsApp
          Expanded(
            child: Column(
              children: [
                // Liste des messages
                Expanded(
                  child: _loadingMessages
                      ? Center(
                          child: CircularProgressIndicator(
                            color: _waAccentGreen,
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                          itemCount: _messages.length + (_botTyping ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_botTyping && index == _messages.length) {
                              return _buildTypingIndicator();
                            }
                            return _buildBubble(_messages[index]);
                          },
                        ),
                ),

                // Barre de saisie style WhatsApp officiel
                Container(
                  color: _inputBarBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.emoji_emotions_outlined,
                            color: _timeTextColor,
                            size: 24,
                          ),
                          onPressed: () {},
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _inputFieldBg,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: TextField(
                              controller: _controller,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 4,
                              minLines: 1,
                              style: TextStyle(
                                color: _inputTextColor,
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Entrez un message...',
                                hintStyle: TextStyle(color: _timeTextColor),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            _isListening ? Icons.stop : Icons.mic,
                            color: _isListening ? Colors.red : _timeTextColor,
                            size: 24,
                          ),
                          tooltip: _isListening
                              ? 'Arrêter l’écoute'
                              : 'Dicter une question',
                          onPressed: _toggleSpeech,
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _sendMessage,
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: _userBubbleBg,
                            child: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
