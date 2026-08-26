// Frida probe for NetEase Cloud Music (com.netease.cloudmusic)
// Goal: reverse-engineer the 5-arg queue update API to implement NextUp's
// skipNext / playPrevious on the NUNeteaseProvider.
//
//   -(void) updateSongList:(id)         // arg1: NSArray of songs (the new full list, or delta)
//                 customRefList:(id)    // arg2: a "reference list" (radio / autoplay?)
//                 refSong:(id)          // arg3: the anchor / "now playing" song
//                 customMode:(long long)// arg4: a mode flag (0..N — semantics unknown)
//                 recoverWhileLoopFinished:(bool)  // arg5: bool
//
// USAGE:
//   1. On the device, open 网易云 (no need to play yet — the script hooks at load).
//   2. On the Windows host (with frida-tools installed and iTunes USB driver present):
//        frida -U -f com.netease.cloudmusic -l tools/probe_netease_queue.js --no-pause
//   3. In 网易云 do: add to queue, skip, switch playlists, enable radio, etc.
//   4. Read the console output to map each arg's role.
//   5. Once semantics are clear, the "test call" block at the bottom lets you
//      invoke the method with crafted args and see how the live queue changes.
//
// Tested API surface (confirmed via Flex 3 on iOS 16 Dopamine-roothide, 2026-08-26):
//   NMSonglistPlayerController:
//     - (void) setupWithSongs:(id) index:(long long) complete:(id)
//     - (id)   currentSong
//     - (id)   playList
//     - (id)   currentRefList
//     - (unsigned long long) _indexOfSong:(id) inSongList:(id)
//     - (void) updateSongList:(id) customRefList:(id) refSong:(id)
//                    customMode:(long long) recoverWhileLoopFinished:(bool)

'use strict';

const CTRL = 'NMSonglistPlayerController';
const M    = '- updateSongList:customRefList:refSong:customMode:recoverWhileLoopFinished:';

// ---------- helpers ----------------------------------------------------------

function hr(label) { console.log('\n=== ' + label + ' ==='); }

function describeSongList(label, list) {
  if (list === null || list === undefined) {
    console.log('  ' + label + ': <nil>');
    return list;
  }
  const cls = list.$className;
  const cnt = (typeof list.count === 'function') ? list.count() : '(no count)';
  console.log('  ' + label + ': class=' + cls + ' count=' + cnt);
  if (typeof list.count === 'function' && cnt > 0 && cnt < 40) {
    for (let i = 0; i < cnt; i++) {
      try {
        const obj = list.objectAtIndex_(i);
        const title = (obj && obj.title) ? obj.title()
                    : (obj && obj.valueForKey_) ? obj.valueForKey_('title')
                    : '?';
        const artist = (obj && obj.artist) ? obj.artist()
                     : (obj && obj.valueForKey_) ? obj.valueForKey_('artist')
                     : '?';
        console.log('    [' + i + '] ' + (obj ? obj.$className : 'nil') +
                    ' title="' + title + '" artist="' + artist + '"');
      } catch (e) {
        console.log('    [' + i + '] <error: ' + e + '>');
      }
    }
  }
  return list;
}

function describeSong(label, song) {
  if (song === null || song === undefined) {
    console.log('  ' + label + ': <nil>');
    return;
  }
  const cls = song.$className;
  let title = '?';
  try { title = song.title ? song.title() : (song.valueForKey_ ? song.valueForKey_('title') : '?'); } catch (e) {}
  let artist = '?';
  try { artist = song.artist ? song.artist() : (song.valueForKey_ ? song.valueForKey_('artist') : '?'); } catch (e) {}
  console.log('  ' + label + ': class=' + cls + ' title="' + title + '" artist="' + artist + '"');
}

// ---------- locate a live instance (lazy) ------------------------------------

function findLiveInstance(cls) {
  if (!cls) return null;
  for (const name of ['sharedInstance', 'sharedPlayerManager', 'sharedController',
                      'defaultInstance', 'currentInstance', 'shared']) {
    if (typeof cls[name] === 'function') {
      try {
        const inst = cls[name]();
        if (inst) return inst;
      } catch (e) { /* keep trying */ }
    }
  }
  if (typeof ObjC.choose !== 'undefined') {
    try {
      const found = ObjC.choose(cls, { limit: 1 });
      if (found && found.length > 0) return found[0];
    } catch (e) {}
  }
  return null;
}

const cls = ObjC.classes[CTRL];
if (!cls) {
  console.log('[!] class ' + CTRL + ' not found in this process');
  console.log('    Make sure frida attached to 网易云 (com.netease.cloudmusic), not SpringBoard.');
  throw new Error('class not found');
}

let inst = findLiveInstance(cls);

function printBaseline() {
  hr('baseline state');
  if (!inst) {
    console.log('  (no live instance yet — start playing a song, it will appear)');
    return;
  }
  console.log('[*] live instance: ' + CTRL);
  let playList = null;
  try { playList = inst.playList(); } catch (e) { console.log('  playList() threw: ' + e); }
  describeSongList('playList', playList);

  let currentRefList = null;
  try { currentRefList = inst.currentRefList(); } catch (e) { console.log('  currentRefList() threw: ' + e); }
  describeSongList('currentRefList', currentRefList);

  let currentSong = null;
  try { currentSong = inst.currentSong(); } catch (e) { console.log('  currentSong() threw: ' + e); }
  describeSong('currentSong', currentSong);
}

printBaseline();

// ---------- hook the 5-arg method (does not need a live instance) -----------

const target = cls[M];
if (!target) {
  console.log('[!] method ' + M + ' not found on ' + CTRL);
  throw new Error('method not found');
}
console.log('[*] hooking ' + M);
Interceptor.attach(target.implementation, {
  onEnter(args) {
    const a1 = new ObjC.Object(args[2]);
    const a2 = new ObjC.Object(args[3]);
    const a3 = new ObjC.Object(args[4]);
    const a4 = args[5].toInt64();   // long long
    const a5 = (args[6].toInt32() !== 0); // bool

    hr('updateSongList CALLED');
    try {
      const bt = Backtrace.fromThisContext().slice(0, 12).map(f => '  at ' + f).join('\n');
      if (bt) console.log(bt);
    } catch (e) {}
    console.log('  arg1 (songList)        : ' + (a1 ? a1.$className : 'nil'));
    describeSongList('  → songList', a1);
    console.log('  arg2 (customRefList)   : ' + (a2 ? a2.$className : 'nil'));
    describeSongList('  → customRefList', a2);
    console.log('  arg3 (refSong)         : ' + (a3 ? a3.$className : 'nil'));
    describeSong('  → refSong', a3);
    console.log('  arg4 (customMode)      : ' + a4);
    console.log('  arg5 (recoverWhileLoop): ' + a5);
  }
});

// ---------- ready + delayed re-baseline --------------------------------------

setTimeout(() => {
  if (!inst) {
    const found = findLiveInstance(cls);
    if (found) { inst = found; printBaseline(); }
  }
  hr('ready — do actions in 网易云, watch logs above');
  console.log('Test-call template (uncomment in script & edit):');
  console.log('  inst.updateSongList_customRefList_refSong_customMode_recoverWhileLoopFinished_(null, null, null, 0, false);');
  console.log('  // then read inst.playList() / inst.currentSong() again to see what changed');
}, 2000);

// Convenience: a "skip the next track" experiment template. Edit and uncomment.
// function trySkipNextExperiment() {
//   const before = inst.playList();
//   const idx = inst._indexOfSong_inSongList_(inst.currentSong(), before);
//   console.log('currentSong index in playList: ' + idx);
//   // build new list without the next element (NSMutableArray wiring — next iteration)
// }
