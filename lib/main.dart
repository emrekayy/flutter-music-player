import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// ===============================================================
///  MÜZİK KUTUSU (SADECE SES) - Tek Dosya main.dart
///  Offline - Hive + SecureStorage
///  Upload (mp3/wav/m4a/aac/ogg) + Liste + Playlist + PlayNext + Delete
/// ===============================================================

const _boxSongs = 'songs';
const _boxPlaylists = 'playlists';

const _keyEmail = 'mk_email';
const _keyHash = 'mk_pass_hash';

const _allowedAudioExt = <String>['mp3', 'wav', 'm4a', 'aac', 'ogg'];

class MediaItem {
  final String id;
  final String title;
  final String filePath;
  final int createdAtMs;

  const MediaItem({
    required this.id,
    required this.title,
    required this.filePath,
    required this.createdAtMs,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'filePath': filePath,
    'createdAtMs': createdAtMs,
  };

  static MediaItem fromMap(Map m) => MediaItem(
    id: (m['id'] ?? '').toString(),
    title: (m['title'] ?? '').toString(),
    filePath: (m['filePath'] ?? '').toString(),
    createdAtMs: int.tryParse((m['createdAtMs'] ?? 0).toString()) ?? 0,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox(_boxSongs);
  await Hive.openBox(_boxPlaylists);
  runApp(const MuzikKutusuApp());
}

class MuzikKutusuApp extends StatelessWidget {
  const MuzikKutusuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Müzik Kutusu',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B0B10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF1DB954),
          secondary: Color(0xFF1DB954),
          surface: Color(0xFF12121A),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// =====================
///  AUTH (offline)
/// =====================
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _storage = const FlutterSecureStorage();
  Future<bool>? _hasAccountFuture;

  @override
  void initState() {
    super.initState();
    _hasAccountFuture = _hasAccount();
  }

  Future<bool> _hasAccount() async {
    final h = await _storage.read(key: _keyHash);
    return (h != null && h.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasAccountFuture,
      builder: (context, snap) {
        final has = snap.data ?? false;
        if (!snap.hasData) return const SplashScreen();
        return has ? const LoginScreen() : const CreatePasswordScreen();
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator()),
      ),
    );
  }
}

String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

class CreatePasswordScreen extends StatefulWidget {
  const CreatePasswordScreen({super.key});

  @override
  State<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _storage = const FlutterSecureStorage();
  final _emailC = TextEditingController();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _emailC.dispose();
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final email = _emailC.text.trim();
    final a = _p1.text;
    final b = _p2.text;

    if (!email.contains('@') || !email.contains('.')) {
      setState(() {
        _busy = false;
        _error = 'Geçerli bir e-posta gir.';
      });
      return;
    }
    if (a.length < 4) {
      setState(() {
        _busy = false;
        _error = 'Şifre en az 4 karakter olsun.';
      });
      return;
    }
    if (a != b) {
      setState(() {
        _busy = false;
        _error = 'Şifreler aynı değil.';
      });
      return;
    }

    await _storage.write(key: _keyEmail, value: email);
    await _storage.write(key: _keyHash, value: _hash(a));

    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Müzik Kutusu',
      subtitle: 'İlk giriş için şifre oluştur',
      child: Column(
        children: [
          _AuthCard(
            children: [
              TextField(
                controller: _emailC,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Gmail / E-posta', hintText: 'ornek@gmail.com'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _p1, obscureText: true, decoration: const InputDecoration(labelText: 'Yeni şifre')),
              const SizedBox(height: 12),
              TextField(controller: _p2, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre tekrar')),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Kaydet'),
                ),
              ),
              const SizedBox(height: 8),
              Opacity(
                opacity: 0.8,
                child: Text(
                  'Bu sürüm tamamen offline. Ses dosyası (mp3 vb.) ekleyip çalabilirsin.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _storage = const FlutterSecureStorage();
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final email = await _storage.read(key: _keyEmail);
    if (email != null) _emailC.text = email;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _error = null;
      _busy = true;
    });

    final emailSaved = (await _storage.read(key: _keyEmail)) ?? '';
    final hashSaved = (await _storage.read(key: _keyHash)) ?? '';

    final email = _emailC.text.trim();
    final pass = _passC.text;

    if (email != emailSaved) {
      setState(() {
        _busy = false;
        _error = 'E-posta yanlış.';
      });
      return;
    }
    if (_hash(pass) != hashSaved) {
      setState(() {
        _busy = false;
        _error = 'Şifre yanlış.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Müzik Kutusu',
      subtitle: 'Giriş yap',
      child: Column(
        children: [
          _AuthCard(
            children: [
              TextField(
                controller: _emailC,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Gmail / E-posta'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _passC, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre')),
              const SizedBox(height: 12),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Giriş Yap'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1DB954), Color(0xFF0B0B10), Color(0xFF0B0B10)],
            stops: [0.0, 0.35, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  final List<Widget> children;
  const _AuthCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF0F0F17),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

/// =====================
///  HOME (Spotify-ish)
/// =====================
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  final _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;

  String? _currentId;
  bool _isPlaying = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  // Queue
  List<String> _queue = <String>[]; // sıradaki şarkı ID listesi
  int _queueIndex = -1; // şu anki index

  @override
  void initState() {
    super.initState();

    _posSub = _player.onPositionChanged.listen((d) {
      if (!mounted) return;
      setState(() => _pos = d);
    });

    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _dur = d);
    });

    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = (s == PlayerState.playing));
    });

    // Şarkı bitince otomatik next
    _completeSub = _player.onPlayerComplete.listen((_) async {
      await playNext();
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Box get _songsBox => Hive.box(_boxSongs);
  Box get _plBox => Hive.box(_boxPlaylists);

  List<MediaItem> _loadItems() {
    final raw = _songsBox.get('items', defaultValue: <dynamic>[]) as List;
    final items = raw
        .whereType<Map>()
        .map((m) => MediaItem.fromMap(Map<String, dynamic>.from(m)))
        .toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return items;
  }

  Map<String, List<String>> _loadPlaylists() {
    final raw = _plBox.get('items', defaultValue: <dynamic>[]) as List;
    final out = <String, List<String>>{};
    for (final it in raw) {
      if (it is Map) {
        final name = (it['name'] ?? '').toString();
        final ids = (it['ids'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (name.isNotEmpty) out[name] = ids;
      }
    }
    return out;
  }

  Future<void> _saveItems(List<MediaItem> items) async {
    await _songsBox.put('items', items.map((e) => e.toMap()).toList());
  }

  Future<void> _savePlaylists(Map<String, List<String>> pls) async {
    final raw = pls.entries.map((e) => {'name': e.key, 'ids': e.value}).toList();
    await _plBox.put('items', raw);
  }

  Future<Directory> _appMediaDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/muzik_kutusu_audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w\s\-\.\(\)\[\]]', unicode: true), '_');
    return cleaned.trim().isEmpty ? 'dosya' : cleaned.trim();
  }

  Future<void> addAudio() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: _allowedAudioExt,
    );
    if (res == null) return;

    final picked = res.files.single;
    final srcPath = picked.path;
    if (srcPath == null) return;

    final srcFile = File(srcPath);
    if (!await srcFile.exists()) return;

    final mediaDir = await _appMediaDir();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // FIX: isim/uzantı güvenli yönetim
    final originalName = _safeName(picked.name);
    final ext = (picked.extension ?? '').toLowerCase();
    final nameNoExt = originalName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
    final safeExt = _allowedAudioExt.contains(ext) ? ext : '';

    final destPath = safeExt.isEmpty
        ? '${mediaDir.path}/$ts-$nameNoExt'
        : '${mediaDir.path}/$ts-$nameNoExt.$safeExt';

    final destFile = await srcFile.copy(destPath);

    final title = nameNoExt;
    final item = MediaItem(
      id: ts.toString(),
      title: title,
      filePath: destFile.path,
      createdAtMs: ts,
    );

    final items = _loadItems();
    items.insert(0, item);
    await _saveItems(items);

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Şarkı eklendi: $title')));
  }

  Future<void> deleteItem(MediaItem item) async {
    if (_currentId == item.id) {
      await _player.stop();
      _currentId = null;
      _pos = Duration.zero;
      _dur = Duration.zero;
      _queueIndex = -1;
    }

    try {
      final f = File(item.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}

    final items = _loadItems()..removeWhere((e) => e.id == item.id);
    await _saveItems(items);

    final pls = _loadPlaylists();
    for (final k in pls.keys.toList()) {
      pls[k] = (pls[k] ?? []).where((id) => id != item.id).toList();
    }
    await _savePlaylists(pls);

    // queue’yu da güncelle
    _queue.removeWhere((id) => id == item.id);
    if (_queueIndex >= _queue.length) _queueIndex = _queue.length - 1;

    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _ensureFilePlayable(MediaItem item) async {
    final f = File(item.filePath);
    if (await f.exists()) return true;

    // Dosya yoksa: kullanıcıya uyarı
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya bulunamadı: ${item.title} (muhtemelen silinmiş)')),
      );
    }
    return false;
  }

  Future<void> togglePlay(MediaItem item) async {
    // aynı parça -> pause/resume
    if (_currentId == item.id && _isPlaying) {
      await _player.pause();
      return;
    }
    if (_currentId == item.id && !_isPlaying) {
      await _player.resume();
      return;
    }

    // yeni parça çal
    final ok = await _ensureFilePlayable(item);
    if (!ok) return;

    await _player.stop();

    final items = _loadItems();
    _queue = items.map((e) => e.id).toList();
    _queueIndex = _queue.indexOf(item.id);

    setState(() {
      _currentId = item.id;
      _pos = Duration.zero;
      _dur = Duration.zero;
    });

    await _player.play(DeviceFileSource(item.filePath));
  }

  Future<void> playNext() async {
    if (_queue.isEmpty) return;
    if (_queueIndex < 0) return;

    final nextIndex = _queueIndex + 1;

    // Liste bitti -> dur
    if (nextIndex >= _queue.length) {
      await _player.stop();
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _pos = Duration.zero;
      });
      return;
    }

    final items = _loadItems();
    final nextId = _queue[nextIndex];

    MediaItem? nextItem;
    try {
      nextItem = items.firstWhere((e) => e.id == nextId);
    } catch (_) {
      nextItem = null;
    }

    // sıradaki silinmişse/ bulunamadıysa -> bir sonrakine geç
    if (nextItem == null) {
      _queueIndex = nextIndex;
      await playNext();
      return;
    }

    // dosya gerçekten var mı?
    final ok = await _ensureFilePlayable(nextItem);
    if (!ok) {
      // dosya yoksa, bu id’yi queue’dan düşür ve tekrar dene
      _queue.removeAt(nextIndex);
      if (_queueIndex >= _queue.length) _queueIndex = _queue.length - 1;
      await playNext();
      return;
    }

    _queueIndex = nextIndex;

    if (!mounted) return;
    setState(() {
      _currentId = nextItem!.id; // nextItem burada kesin null değil
      _pos = Duration.zero;
      _dur = Duration.zero;
    });

    await _player.stop();
    await _player.play(DeviceFileSource(nextItem.filePath));
  }

  MediaItem? _currentItem() {
    if (_currentId == null) return null;
    final items = _loadItems();
    try {
      return items.firstWhere((e) => e.id == _currentId);
    } catch (_) {
      return null;
    }
  }

  Future<void> createPlaylist() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Yeni playlist'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'Örn: Spor Modu')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oluştur')),
        ],
      ),
    );
    if (ok != true) return;

    final name = c.text.trim();
    if (name.isEmpty) return;

    final pls = _loadPlaylists();
    if (pls.containsKey(name)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bu isimde playlist var.')));
      return;
    }
    pls[name] = <String>[];
    await _savePlaylists(pls);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> addToPlaylist(MediaItem item) async {
    final pls = _loadPlaylists();
    if (pls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Önce playlist oluştur.')));
      return;
    }

    String selected = pls.keys.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Playlist’e ekle'),
        content: StatefulBuilder(
          builder: (context, setSt) => DropdownButtonFormField<String>(
            value: selected,
            items: pls.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: (v) => setSt(() => selected = v ?? selected),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ekle')),
        ],
      ),
    );
    if (ok != true) return;

    final list = (pls[selected] ?? <String>[]);
    if (!list.contains(item.id)) list.add(item.id);
    pls[selected] = list;
    await _savePlaylists(pls);

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eklendi → $selected')));
  }

  Future<void> removeFromPlaylist(String playlist, String id) async {
    final pls = _loadPlaylists();
    pls[playlist] = (pls[playlist] ?? []).where((x) => x != id).toList();
    await _savePlaylists(pls);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> logout() async {
    await _player.stop();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
  }

  Future<void> clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Her şeyi sil'),
        content: const Text('Tüm şarkılar + playlistler + dosyalar silinecek. Emin misin?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true) return;

    await _player.stop();
    _currentId = null;
    _queue = <String>[];
    _queueIndex = -1;

    try {
      final dir = await _appMediaDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}

    await _songsBox.put('items', <dynamic>[]);
    await _plBox.put('items', <dynamic>[]);

    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryPage(
        items: _loadItems(),
        isPlaying: _isPlaying,
        currentId: _currentId,
        onAdd: addAudio,
        onPlay: togglePlay,
        onDelete: deleteItem,
        onAddToPlaylist: addToPlaylist,
      ),
      PlaylistsPage(
        playlists: _loadPlaylists(),
        allItems: _loadItems(),
        currentId: _currentId,
        isPlaying: _isPlaying,
        onCreate: createPlaylist,
        onPlay: togglePlay,
        onRemoveFromPlaylist: removeFromPlaylist,
      ),
      SettingsPage(onLogout: logout, onClearAll: clearAll),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(
            item: _currentItem(),
            isPlaying: _isPlaying,
            pos: _pos,
            dur: _dur,
            onToggle: () async {
              final it = _currentItem();
              if (it == null) return;
              await togglePlay(it);
            },
            onSeek: (v) async {
              final ms = (v * (_dur.inMilliseconds == 0 ? 1 : _dur.inMilliseconds)).round();
              await _player.seek(Duration(milliseconds: ms));
            },
          ),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.library_music), label: 'Kütüphane'),
              NavigationDestination(icon: Icon(Icons.queue_music), label: 'Playlist'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Ayarlar'),
            ],
          ),
        ],
      ),
    );
  }
}

class LibraryPage extends StatefulWidget {
  final List<MediaItem> items;
  final bool isPlaying;
  final String? currentId;
  final VoidCallback onAdd;
  final Future<void> Function(MediaItem) onPlay;
  final Future<void> Function(MediaItem) onDelete;
  final Future<void> Function(MediaItem) onAddToPlaylist;

  const LibraryPage({
    super.key,
    required this.items,
    required this.isPlaying,
    required this.currentId,
    required this.onAdd,
    required this.onPlay,
    required this.onDelete,
    required this.onAddToPlaylist,
  });

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.items.where((e) {
      if (_q.trim().isEmpty) return true;
      return e.title.toLowerCase().contains(_q.trim().toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopHeader(
            title: 'Müzik Kutusu',
            subtitle: 'Dosya ekle, sakla, dinle (offline)',
            trailing: FilledButton.icon(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Şarkı Ekle'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Ara: şarkı...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFF12121A),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: list.isEmpty
                ? const _EmptyState(
              title: 'Henüz şarkı yok',
              subtitle: '“Şarkı Ekle” ile mp3 ekle. Uygulama telefona kopyalar.',
              icon: Icons.library_music,
            )
                : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final it = list[i];
                final isCurrent = (widget.currentId == it.id);
                final playingThis = isCurrent && widget.isPlaying;

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF0F0F17),
                      child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary),
                    ),
                    title: Text(
                      it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('Ses', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Playlist’e ekle',
                          onPressed: () => widget.onAddToPlaylist(it),
                          icon: const Icon(Icons.playlist_add),
                        ),
                        IconButton(
                          tooltip: playingThis ? 'Duraklat' : 'Oynat',
                          onPressed: () => widget.onPlay(it),
                          icon: Icon(playingThis ? Icons.pause_circle : Icons.play_circle),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'delete') await widget.onDelete(it);
                            if (v == 'play') await widget.onPlay(it);
                            if (v == 'addpl') await widget.onAddToPlaylist(it);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'play', child: Text('Oynat/Durdur')),
                            PopupMenuItem(value: 'addpl', child: Text('Playlist’e ekle')),
                            PopupMenuDivider(),
                            PopupMenuItem(value: 'delete', child: Text('Sil')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PlaylistsPage extends StatelessWidget {
  final Map<String, List<String>> playlists;
  final List<MediaItem> allItems;
  final String? currentId;
  final bool isPlaying;
  final VoidCallback onCreate;
  final Future<void> Function(MediaItem) onPlay;
  final Future<void> Function(String playlist, String id) onRemoveFromPlaylist;

  const PlaylistsPage({
    super.key,
    required this.playlists,
    required this.allItems,
    required this.currentId,
    required this.isPlaying,
    required this.onCreate,
    required this.onPlay,
    required this.onRemoveFromPlaylist,
  });

  MediaItem? _byId(String id) {
    try {
      return allItems.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = playlists.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TopHeader(
            title: 'Çalma Listeleri',
            subtitle: 'Kendi listeni oluştur',
            trailing: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Playlist'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: names.isEmpty
                ? const _EmptyState(
              title: 'Playlist yok',
              subtitle: '“Playlist” butonuyla oluştur.',
              icon: Icons.queue_music,
            )
                : ListView.separated(
              itemCount: names.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final name = names[i];
                final ids = playlists[name] ?? const <String>[];
                final items = ids.map(_byId).whereType<MediaItem>().toList();

                return Card(
                  child: ExpansionTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${items.length} şarkı'),
                    children: [
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Text(
                            'Bu playlist boş. Kütüphane → “Playlist’e ekle” yap.',
                            style: TextStyle(color: Colors.white.withOpacity(0.7)),
                          ),
                        ),
                      for (final it in items)
                        ListTile(
                          leading: Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary),
                          title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                tooltip: 'Oynat/Durdur',
                                onPressed: () => onPlay(it),
                                icon: Icon((currentId == it.id && isPlaying) ? Icons.pause_circle : Icons.play_circle),
                              ),
                              IconButton(
                                tooltip: 'Playlist’ten çıkar',
                                onPressed: () => onRemoveFromPlaylist(name, it.id),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final Future<void> Function() onLogout;
  final Future<void> Function() onClearAll;

  const SettingsPage({
    super.key,
    required this.onLogout,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TopHeader(title: 'Ayarlar', subtitle: 'Hızlı işlemler'),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Çıkış yap'),
                  subtitle: const Text('Giriş ekranına dön'),
                  onTap: onLogout,
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Her şeyi temizle'),
                  subtitle: const Text('Tüm şarkılar + playlistler + dosyalar silinir'),
                  onTap: onClearAll,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================
///  Mini Player
/// =====================
class MiniPlayer extends StatelessWidget {
  final MediaItem? item;
  final bool isPlaying;
  final Duration pos;
  final Duration dur;
  final VoidCallback onToggle;
  final Future<void> Function(double v) onSeek;

  const MiniPlayer({
    super.key,
    required this.item,
    required this.isPlaying,
    required this.pos,
    required this.dur,
    required this.onToggle,
    required this.onSeek,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (item == null) return const SizedBox.shrink();

    final totalMs = dur.inMilliseconds;
    final p = totalMs <= 0 ? 0.0 : (pos.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF0F0F17),
            child: Icon(Icons.music_note, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: p,
                        onChanged: (v) => onSeek(v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('${_fmt(pos)} / ${_fmt(dur)}', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onToggle,
            icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle),
            iconSize: 34,
          ),
        ],
      ),
    );
  }
}

/// =====================
///  Small UI helpers
/// =====================
class _TopHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _TopHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.75))),
          ]),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.7))),
            ],
          ),
        ),
      ),
    );
  }
}