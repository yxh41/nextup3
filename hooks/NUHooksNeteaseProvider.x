// NetEase Cloud Music provider hooks (com.netease.cloudmusic). Capture the live
// queue controller on each playlist setup so the provider can read playList /
// currentRefList / currentSong and edit the queue. Parallel to
// NUHooksSpotifyProvider.x / NUHooksMusicProvider.x / etc.
//
// NMSonglistPlayerController API confirmed via Flex 3 on iOS 16 (Dopamine-roothide,
// com.netease.cloudmusic):
//   -(void) setupWithSongs:(id) index:(long long) complete:(id)
//   -(id)  currentSong
//   -(id)  playList
//   -(id)  currentRefList
//   -(unsigned long long) _indexOfSong:(id) inSongList:(id)
//   -(void) updateSongList:(id) customRefList:(id) refSong:(id) customMode:(long long) recoverWhileLoopFinished:(bool)
#import "NUHooksShared.h"
#import "NUNeteaseProvider.h"

%group NeteaseProvider

%hook NMSonglistPlayerController
- (void)setupWithSongs:(id)songs index:(long long)index complete:(id)complete {
    %orig;
    [[NUNeteaseProvider shared] capturePlayer:self];
    NULog("netease: setupWithSongs index=%lld songs=%lu",
          index, (unsigned long)[(NSArray *)songs count]);
}

// Broad capture net. setupWithSongs:index:complete: is not guaranteed to fire on
// every playback path (e.g. resume, radio, "play" from a detail page), and without
// a captured controller the provider can only report inactive. -currentSong is a
// plain getter that is queried constantly while music plays, so capturing from
// here guarantees we hold a live controller shortly after playback starts.
- (id)currentSong {
    [[NUNeteaseProvider shared] capturePlayer:self];
    return %orig;
}
%end

%end // NeteaseProvider

%ctor {
    @autoreleasepool {
        NUApplySandbox(); // grant shared mach service access (idempotent across ctors)
        if (!NUIsNetease()) return;
        %init(NeteaseProvider);
        [[NUNeteaseProvider shared] startServer];
        NULog("loaded into NetEase Cloud Music (provider)");
#ifdef DEBUG
        // Interface drift probe (dev builds only): after a NetEase update, a missing
        // class here is the first thing to check when the row goes blank.
        // Class c = objc_getClass("NMSonglistPlayerController");
        // if (!c) NULog("netease probe: NMSonglistPlayerController MISSING");
#endif
    }
}
