import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final user = FirebaseAuth.instance.currentUser;
  final picker = ImagePicker();
  bool _isUploading = false;

  Future<void> _uploadImage() async {
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isUploading = true);
    final file = File(pickedFile.path);

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('user_uploads/${user!.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(file);
      final url = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('uploads').add({
        'url': url,
        'userId': user!.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploaded successfully ✅')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed: $e")),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  /// ✅ FIXED DOWNLOAD FUNCTION (Scoped Storage + iOS Safe)
  Future<void> _downloadFile(String url) async {
    try {
      // Ask permission (only for Android < 13)
      if (Platform.isAndroid) {
        final androidVersion = int.tryParse(
            (await _getAndroidVersion())?.split('.')?.first ?? '13');
        if (androidVersion != null && androidVersion < 13) {
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Storage permission denied 🚫')),
            );
            return;
          }
        }
      }

      // Create a CloudVaultora folder in Download directory
      Directory? downloadDir;
      if (Platform.isAndroid) {
        downloadDir = Directory('/storage/emulated/0/Download/CloudVaultora');
      } else {
        downloadDir = await getApplicationDocumentsDirectory();
      }
      if (!(await downloadDir.exists())) {
        await downloadDir.create(recursive: true);
      }

      final fileName = p.basename(Uri.parse(url).path);
      final file = File('${downloadDir.path}/$fileName');

      final response = await http.get(Uri.parse(url));
      await file.writeAsBytes(response.bodyBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Saved to: ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Download failed: $e')),
      );
    }
  }

  Future<String?> _getAndroidVersion() async {
    try {
      final file = File('/system/build.prop');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.startsWith('ro.build.version.release=')) {
            return line.split('=')[1];
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _deleteImage(String docId, String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete image?'),
        content: const Text('This will permanently remove it from your cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final scaffold = ScaffoldMessenger.of(context);
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      await ref.delete();
      await FirebaseFirestore.instance.collection('uploads').doc(docId).delete();
      scaffold.showSnackBar(const SnackBar(content: Text('Deleted successfully ✅')));
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _openViewer(int startIndex, List<QueryDocumentSnapshot> docs) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullscreenViewer(
          startIndex: startIndex,
          docs: docs,
          onDownload: (url) => _downloadFile(url),
          onDelete: (docId, url) async {
            await _deleteImage(docId, url);
            if (mounted) Navigator.of(context).pop();
          },
        ),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = user?.email?.split('@').first ?? 'User';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'CloudVaultora ☁️',
          style: TextStyle(
            color: Color(0xFF1D1D1F),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white.withOpacity(0.3),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.black87),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/auth');
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF8B9DAA),
              Color(0xFFF2F6FF),
              Color(0xFFE9F1FF),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome $username 👋",
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D1D1F),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Your recent uploads",
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('uploads')
                        .where('userId', isEqualTo: user?.uid)
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "No uploads yet ☁️\nTap the cloud button below to upload!",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54, fontSize: 16),
                          ),
                        );
                      }

                      return GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final imageUrl = data['url'] ?? '';

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: GestureDetector(
                              onTap: () => _openViewer(index, docs),
                              onLongPress: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (c) => SafeArea(
                                    child: Wrap(
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.download_rounded),
                                          title: const Text('Download'),
                                          onTap: () {
                                            Navigator.pop(c);
                                            _downloadFile(imageUrl);
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.delete_outline, color: Colors.red),
                                          title: const Text('Delete', style: TextStyle(color: Colors.red)),
                                          onTap: () {
                                            Navigator.pop(c);
                                            _deleteImage(docs[index].id, imageUrl);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white.withOpacity(0.4)),
                                ),
                                child: imageUrl.isNotEmpty
                                    ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return Container(
                                      color: Colors.white.withOpacity(0.2),
                                      child: const Center(
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    );
                                  },
                                )
                                    : const Icon(Icons.insert_drive_file_rounded,
                                    color: Colors.white, size: 30),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _isUploading
          ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3A7BD5)))
          : Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF3A7BD5), Color(0xFF00D2FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF3A7BD5).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: _uploadImage,
          child: const Icon(Icons.cloud_upload_rounded, size: 32, color: Colors.white),
        ),
      ),
    );
  }
}

/// Fullscreen viewer (unchanged)
class _FullscreenViewer extends StatefulWidget {
  final int startIndex;
  final List<QueryDocumentSnapshot> docs;
  final void Function(String url) onDownload;
  final Future<void> Function(String docId, String url) onDelete;

  const _FullscreenViewer({
    required this.startIndex,
    required this.docs,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends State<_FullscreenViewer> {
  late PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.startIndex;
    _pageController = PageController(initialPage: _current);
  }

  @override
  Widget build(BuildContext context) {
    final docs = widget.docs;
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: docs.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final url = data['url'] ?? '';
                return Center(
                  child: InteractiveViewer(
                    child: url.isNotEmpty
                        ? Image.network(url, fit: BoxFit.contain)
                        : const Icon(Icons.broken_image, color: Colors.white, size: 80),
                  ),
                );
              },
            ),
            Positioned(
              top: 12,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: 12,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    onPressed: () {
                      final data = docs[_current].data() as Map<String, dynamic>;
                      widget.onDownload(data['url'] ?? '');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: () async {
                      final data = docs[_current].data() as Map<String, dynamic>;
                      final docId = docs[_current].id;
                      await widget.onDelete(docId, data['url'] ?? '');
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_current + 1} / ${docs.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
