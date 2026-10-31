part of 'player_lyrics.dart';

extension _SyncedLyricsViewStateDelegates1 on _SyncedLyricsViewState {
  void _didChangeAppLifecycleStateImpl(AppLifecycleState state) {
    // A change that keeps the view on screen leaves the lyrics running.
    if ((_positionSubscription != null) != _visible) {
      _syncPositionSubscription(resetUserScroll: false);
    }
    if (mounted) _rebuild(() {});
  }

  Widget _buildImpl(BuildContext context) => LyricsTextScale(
    child: TweenAnimationBuilder<Offset>(
      tween: Tween(
        end: Offset(
          widget.showPronunciation ? 1 : 0,
          widget.showTranslation ? 1 : 0,
        ),
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      builder: (context, visibility, _) => _buildLyrics(context, visibility),
    ),
  );
}
