import 'package:flutter/foundation.dart';

import '../../services/api_client.dart';
import 'profile_models.dart';
import 'profile_repository.dart';

enum ProfileStatus { loading, loaded, error }
enum VideosStatus { idle, loading, loaded, error }

/// Manages the state for a single profile page.
class ProfileController extends ChangeNotifier {
  ProfileController(this._repo, {required this.userId}) {
    load();
  }

  final ProfileRepository _repo;
  final String userId;

  ProfileStatus _status = ProfileStatus.loading;
  ProfileStatus get status => _status;

  UserProfile? _profile;
  UserProfile? get profile => _profile;

  String? _error;
  String? get error => _error;

  // --- Videos ---
  VideosStatus _videosStatus = VideosStatus.idle;
  VideosStatus get videosStatus => _videosStatus;
  final List<ProfilePost> _videos = [];
  List<ProfilePost> get videos => List.unmodifiable(_videos);
  String? _videosCursor;
  bool get hasMoreVideos => _videosCursor != null;

  // --- Bookmarks (owner only) ---
  List<Bookmark>? _bookmarks;
  List<Bookmark>? get bookmarks => _bookmarks;
  bool _bookmarksLoaded = false;

  Future<void> load() async {
    _status = ProfileStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _profile = await _repo.getProfile(userId);
      _status = ProfileStatus.loaded;
    } on ApiException catch (e) {
      _error = e.message;
      _status = ProfileStatus.error;
    } on Object catch (e) {
      _error = 'Could not load this profile.';
      _status = ProfileStatus.error;
      debugPrint('Profile load error: $e');
    }
    notifyListeners();
  }

  Future<void> loadVideos() async {
    if (_videosStatus == VideosStatus.loading) return;
    _videosStatus = VideosStatus.loading;
    notifyListeners();
    try {
      final result = await _repo.getUserVideos(userId, cursor: _videosCursor);
      _videos.addAll(result.posts);
      _videosCursor = result.nextCursor;
      _videosStatus = VideosStatus.loaded;
    } on ApiException catch (e) {
      _error = e.message;
      _videosStatus = VideosStatus.error;
    } on Object catch (e) {
      _videosStatus = VideosStatus.error;
      debugPrint('Videos load error: $e');
    }
    notifyListeners();
  }

  Future<void> refreshVideos() async {
    _videos.clear();
    _videosCursor = null;
    _videosStatus = VideosStatus.idle;
    notifyListeners();
    await loadVideos();
  }

  Future<void> loadBookmarks() async {
    if (_bookmarksLoaded || _profile?.isMe != true) return;
    try {
      _bookmarks = await _repo.getBookmarks();
      _bookmarksLoaded = true;
    } on ApiException catch (e) {
      debugPrint('Bookmarks error: ${e.message}');
    }
    notifyListeners();
  }

  Future<bool> toggleFollow() async {
    final p = _profile;
    if (p == null || p.isMe) return false;
    final newState = !p.followedByMe;
    // Optimistic update
    _profile = UserProfile(
      user: p.user,
      bio: p.bio,
      followerCount: p.followerCount + (newState ? 1 : -1),
      followingCount: p.followingCount,
      postCount: p.postCount,
      followedByMe: newState,
      blockedByMe: p.blockedByMe,
      isMe: p.isMe,
      personality: p.personality,
      credibility: p.credibility,
      contributions: p.contributions,
    );
    notifyListeners();
    try {
      await _repo.setFollowing(userId, newState);
      return true;
    } on Object {
      // Revert
      _profile = p;
      notifyListeners();
      return false;
    }
  }

  String mediaUrl(String path) => _repo.mediaUrl(path);
}
