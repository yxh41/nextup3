#import "NUNeteaseProvider.h"
#import "NUShared.h"
#import "LightMessaging.h"
#import <notify.h>
#import <UIKit/UIKit.h>

// ─────────────────────────────────────────────────────────────────────────────
// NMSonglistPlayerController queue API — confirmed via Flex 3 on iOS 16
// Dopamine-roothide (com.netease.cloudmusic):
//
//   -(void) setupWithSongs:(id) index:(long long) complete:(id)
//   -(id)  currentSong
//   -(id)  playList                                // NSArray of NM* track objects
//   -(id)  currentRefList                          // likely the "up next" ref list
//   -(unsigned long long) _indexOfSong:(id) inSongList:(id)
//   -(void) updateSongList:(id) customRefList:(id) refSong:(id)
//                  customMode:(long long) recoverWhileLoopFinished:(bool)
//
// Read path: -nextUpDictionary uses playList + currentSong + _indexOfSong:
// to find the "next" track, KVC @"title"/@"artist" for fields. Mutation
// (skipNext/PlayPrev): blocked on mapping the 5-arg updateSongList:... semantics.
// ─────────────────────────────────────────────────────────────────────────────

#pragma mark - Private NetEase interfaces (confirmed via Flex 3)

// @interface NMSonglistPlayerController : NSObject
// - (id)playList;                                 // CONFIRMED: full loaded list
// - (id)currentSong;                              // CONFIRMED: now-playing track
// - (id)currentRefList;                           // CONFIRMED: "up next" ref list
// - (unsigned long long)_indexOfSong:(id)inSongList:(id);  // CONFIRMED
// - (void)updateSongList:(id)customRefList:(id)refSong:(id)
//                customMode:(long long)recoverWhileLoopFinished:(bool); // CONFIRMED (args TBD)
// - (void)setupWithSongs:(id)index:(long long)complete:(id); // CONFIRMED (capture point)
// @end
//
// Track class: not yet confirmed. KVC @"title"/@"artist" is used so we don't
// need the exact NM* class name. If KVC returns nil, search All Classes in
// Flex (likely candidates: NMSong / NMMusic / NMSongInfo).

#pragma mark - Provider

@interface NUNeteaseProvider ()
@property (nonatomic, weak) id capturedPlayer; // NMSonglistPlayerController live instance (weak to avoid retain cycle)
@end

@implementation NUNeteaseProvider

+ (instancetype)shared {
    static NUNeteaseProvider *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NUNeteaseProvider new]; });
    return s;
}

- (NSString *)appPrefKey { return @"enabledNetease"; }

- (void)capturePlayer:(id)player {
    if (!player || self.capturedPlayer == player) return;
    self.capturedPlayer = player;
    NULog("netease provider: captured player %p", player);
}

// ── Queue reading ────────────────────────────────────────────────────────────
// Read the live up-next from the captured NMSonglistPlayerController. Confirmed
// API: playList / currentSong / _indexOfSong:inSongList:. Title/artist via KVC
// so we don't need the track class name yet (discover later if KVC fails).
- (NSDictionary *)nextUpDictionary {
    if (![self providerEnabled]) return @{ kNUKeyActive : @NO };
    id player = self.capturedPlayer;
    if (!player) return @{ kNUKeyActive : @NO };
    @try {
        // Class-drift guard: respondToSelector: lets us degrade to inactive if
        // NetEase renames a selector in a future update, instead of crashing.
        SEL sList  = @selector(playList);
        SEL sCur   = @selector(currentSong);
        SEL sIndex = @selector(_indexOfSong:inSongList:);
        if (![player respondsToSelector:sList] ||
            ![player respondsToSelector:sCur]  ||
            ![player respondsToSelector:sIndex]) {
            return @{ kNUKeyActive : @NO };
        }
        NSArray *list = (NSArray *)[player performSelector:sList];
        if (![list isKindOfClass:[NSArray class]] || list.count < 2) {
            return @{ kNUKeyActive : @NO };
        }
        id cur = [player performSelector:sCur];
        if (!cur) return @{ kNUKeyActive : @NO };
        unsigned long long idx = (unsigned long long)
            [player performSelector:sIndex withObject:cur withObject:list];
        const unsigned long long kNotFound = (unsigned long long)-1;
        if (idx == kNotFound || idx + 1 >= (unsigned long long)list.count) {
            return @{ kNUKeyActive : @NO };
        }
        id next = list[idx + 1];
        // KVC is resilient to track-class renames; falls back to @"" if absent.
        NSString *title  = [next valueForKey:@"title"]  ?: @"";
        id artistAny = [next valueForKey:@"artist"] ?: [next valueForKey:@"artistsName"];
        NSString *artist = [artistAny isKindOfClass:[NSString class]] ? (NSString *)artistAny : @"";
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[kNUKeyActive]   = @YES;
        d[kNUKeyTitle]    = title;
        d[kNUKeySubtitle] = artist;
        d[kNUKeyCanSkip]  = @YES;
        return d;
    } @catch (__unused NSException *e) {
        return @{ kNUKeyActive : @NO };
    }
}

// ── Actions ──────────────────────────────────────────────────────────────────
// skip = remove the next track from NetEase's queue WITHOUT playing it.
// Candidate mutation API: -updateSongList:customRefList:refSong:customMode:
// recoverWhileLoopFinished: (confirmed exists). The 5-arg semantics still need
// a focused Flex/Frida session to map (call with known inputs, observe state).
// Until then, log and no-op so the row stays correct.
- (void)skipNext {
    NULog("netease skip: TODO (5-arg updateSongList:... arg semantics unmapped)");
}

// re-queue the previously-played track to play NEXT (Apple Music "Play Next"
// semantic). NetEase's queue is in-process, so this is a provider-side re-enqueue
// driven by the kNUPrevNotificationNetease signal from the display. Same blocker
// as skipNext: the queue-mutation API (updateSongList:...) needs arg semantics
// mapped. Until then, no-op.
- (void)playPrevious {
    NULog("netease prev: TODO (5-arg updateSongList:... arg semantics unmapped)");
}

// -jumpToNext is intentionally NOT overridden: NetEase maps the MediaRemote NextTrack
// command to a real advance, so the display sends that command directly (jump:NULL in
// -startServer). Override here only if NetEase mis-maps it on a given iOS version.

#pragma mark - LightMessaging server

- (void)startServer {
    // No jump notification (see note above): display sends MediaRemote NextTrack directly.
    [self startServerWithService:kNUServiceNameNetease
                            skip:kNUSkipNotificationNetease
                            prev:kNUPrevNotificationNetease
                            jump:NULL];
}

@end
