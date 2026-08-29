import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../services/relay/relay_api_client.dart';

/// Grid view of a shared album's images (`GET /images/pairing/:id`),
/// fetched straight from [RelayApiClient] rather than going through
/// `SharedAlbumPhotoSource` - that abstraction targets the slideshow
/// engine's `PhotoItem` shape, while this screen wants the richer
/// management actions (hide/delete) `images.ts` exposes directly.
class SharedAlbumViewScreen extends StatefulWidget {
  const SharedAlbumViewScreen({
    super.key,
    required this.pairingId,
    required this.apiClient,
    required this.localFrameId,
  });

  final String pairingId;
  final RelayApiClient apiClient;
  final String localFrameId;

  @override
  State<SharedAlbumViewScreen> createState() => _SharedAlbumViewScreenState();
}

class _SharedAlbumViewScreenState extends State<SharedAlbumViewScreen> {
  List<RemoteImage> _images = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.apiClient.listImages(widget.pairingId);
    if (!mounted) return;
    result.when(
      onOk: (images) => setState(() => _images = images),
      onErr: (failure) => setState(() => _error = failure.message),
    );
    setState(() => _loading = false);
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await widget.apiClient.tokenStorage.deviceToken;
    return token == null ? {} : {'Authorization': 'Bearer $token'};
  }

  String _thumbUrl(String imageId) => '${widget.apiClient.baseUrl}/api/v1/images/$imageId/file?variant=thumb';

  Future<void> _showActions(RemoteImage image) async {
    final isMine = image.uploadedByFrameId == widget.localFrameId;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off),
              title: const Text('Für mich ausblenden'),
              onTap: () => Navigator.pop(ctx, 'hide'),
            ),
            if (isMine)
              ListTile(
                leading: Icon(Icons.delete, color: Theme.of(ctx).colorScheme.error),
                title: const Text('Löschen'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );

    if (action == null) return;

    final result = action == 'hide'
        ? await widget.apiClient.hideImage(image.id)
        : await widget.apiClient.deleteImage(image.id);

    if (!mounted) return;
    result.when(
      onOk: (_) => _load(),
      onErr: (f) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemeinsames Album'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _images.isEmpty
                  ? const Center(child: Text('Noch keine Fotos hochgeladen.'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: _images.length,
                      itemBuilder: (context, index) {
                        final image = _images[index];
                        return GestureDetector(
                          onTap: () => _showActions(image),
                          child: FutureBuilder<Map<String, String>>(
                            future: _authHeaders(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const ColoredBox(color: Colors.black12);
                              return CachedNetworkImage(
                                imageUrl: _thumbUrl(image.id),
                                httpHeaders: snapshot.data,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => const ColoredBox(color: Colors.black12),
                                errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                              );
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}
