#import "NUProviderBase.h"

// Runs inside com.netease.cloudmusic. Reads the live player's up-next queue, serves the current
// "next up" over LightMessaging, and performs skip / previous. Parallel to NUSpotifyProvider /
// NUMusicProvider / NUPodcastProvider / NUYouTubeMusicProvider.
//
// ⚠️ REVERSE-ENGINEERING TODO: the private NetEase classes and their queue / next-track
// accessors are NOT filled in yet. They must be recovered from a decrypted NetEase Cloud Music
// IPA via class-dump + Frida before this provider actually shows anything. The most promising
// internal class is `NMSonglistPlayerController` (setupWithSongs:index:complete:) — the "up next"
// cache very likely lives there or in `NMPlayerManager`. Reference class names:
// https://github.com/brotherand2/neteasemusic
//
// Until then, every method degrades safely: -nextUpDictionary returns inactive and the actions
// are no-ops, so the Settings toggle still appears and the row never crashes the app.
@interface NUNeteaseProvider : NUProviderBase
+ (instancetype)shared;
- (void)startServer;
// Capture the live player / queue controller from the NetEase hooks
// (hooks/NUHooksNeteaseProvider.x). A fallback instance can be captured here too.
- (void)capturePlayer:(id)player;
@end
