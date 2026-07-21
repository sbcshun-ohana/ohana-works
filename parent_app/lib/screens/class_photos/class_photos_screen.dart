import 'package:flutter/material.dart';

import '../../models/class_photo.dart';
import '../../models/linked_child.dart';
import '../../services/guardian_service.dart';
import '../../theme/app_theme.dart';

/// クラス写真の閲覧(公開済みのみ)。園から掲載確認を経た写真だけが表示される。
class ClassPhotosScreen extends StatefulWidget {
  const ClassPhotosScreen({super.key, required this.guardianService, required this.child});

  final GuardianService guardianService;
  final LinkedChild child;

  @override
  State<ClassPhotosScreen> createState() => _ClassPhotosScreenState();
}

class _ClassPhotosScreenState extends State<ClassPhotosScreen> {
  Future<_ClassPhotosData>? _dataFuture;

  @override
  void initState() {
    super.initState();
    if (widget.child.classId != null) {
      _dataFuture = _load(widget.child.classId!);
    }
  }

  Future<_ClassPhotosData> _load(String classId) async {
    final photos = await widget.guardianService.fetchClassPhotos(classId);
    final urls = <String, String>{};
    await Future.wait(photos.map((photo) async {
      final url = await widget.guardianService.createClassPhotoSignedUrl(photo.storagePath);
      if (url != null) urls[photo.id] = url;
    }));
    return _ClassPhotosData(photos: photos, signedUrls: urls);
  }

  String _formatDate(DateTime d) => '${d.year}/${d.month}/${d.day}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.child.nameLabel}のクラス写真')),
      body: widget.child.classId == null
          ? const Center(
              child: Text('クラス情報が確認できません', style: TextStyle(color: AppColors.textSecondary)),
            )
          : FutureBuilder<_ClassPhotosData>(
              future: _dataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data;
                if (data == null || data.photos.isEmpty) {
                  return const Center(
                    child: Text('公開された写真はまだありません', style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: data.photos.length,
                  itemBuilder: (context, index) {
                    final photo = data.photos[index];
                    final url = data.signedUrls[photo.id];
                    return GestureDetector(
                      onTap: url == null
                          ? null
                          : () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => _ClassPhotoViewerScreen(
                                    url: url,
                                    label: _formatDate(photo.businessDate),
                                  ),
                                ),
                              ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: url == null
                            ? Container(color: AppColors.background)
                            : Image.network(
                                url,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) =>
                                    progress == null ? child : const Center(child: CircularProgressIndicator()),
                                errorBuilder: (context, error, stack) =>
                                    const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textSecondary)),
                              ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _ClassPhotosData {
  const _ClassPhotosData({required this.photos, required this.signedUrls});
  final List<ClassPhoto> photos;
  final Map<String, String> signedUrls;
}

class _ClassPhotoViewerScreen extends StatelessWidget {
  const _ClassPhotoViewerScreen({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
