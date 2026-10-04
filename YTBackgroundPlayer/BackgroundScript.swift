import Foundation

/// Injected into every YouTube page at document start.
/// - Makes the page believe it is always visible, so YouTube does not pause
///   itself when the app goes to the background or the screen locks.
/// - Re-starts the video if WebKit pauses it while backgrounded.
/// - Reports playback state to the native side and exposes `window.__bgPlay`
///   so lock-screen / Control Center commands can drive the player.
enum BackgroundScript {
    static let messageName = "bgPlay"

    static let source = #"""
    (function () {
      if (window.__bgPlay) return;

      // 1) Always report "visible".
      try {
        var define = function (name, value) {
          Object.defineProperty(Document.prototype, name, {
            configurable: true,
            get: function () { return value; }
          });
        };
        define('hidden', false);
        define('webkitHidden', false);
        define('visibilityState', 'visible');
        define('webkitVisibilityState', 'visible');
      } catch (e) {}

      var swallow = function (e) { e.stopImmediatePropagation(); };
      ['visibilitychange', 'webkitvisibilitychange'].forEach(function (type) {
        document.addEventListener(type, swallow, true);
        window.addEventListener(type, swallow, true);
      });

      // 2) Player control + state reporting.
      var state = { background: false, userPaused: false };

      var video = function () {
        var list = document.querySelectorAll('video');
        for (var i = 0; i < list.length; i++) {
          if (list[i].currentSrc || list[i].src) return list[i];
        }
        return list[0] || null;
      };

      var cleanTitle = function () {
        var md = navigator.mediaSession && navigator.mediaSession.metadata;
        if (md && md.title) return md.title;
        return (document.title || '').replace(/\s*-\s*YouTube\s*$/, '');
      };

      var post = function () {
        var v = video();
        var md = navigator.mediaSession && navigator.mediaSession.metadata;
        var art = '';
        if (md && md.artwork && md.artwork.length) {
          art = md.artwork[md.artwork.length - 1].src || '';
        }
        var msg = {
          hasVideo: !!v,
          playing: !!(v && !v.paused && !v.ended),
          title: cleanTitle(),
          artist: (md && md.artist) || '',
          artwork: art,
          duration: (v && isFinite(v.duration)) ? v.duration : 0,
          currentTime: v ? v.currentTime : 0,
          rate: v ? v.playbackRate : 1
        };
        try { window.webkit.messageHandlers.bgPlay.postMessage(msg); } catch (e) {}
      };

      var clickFirst = function (selectors) {
        for (var i = 0; i < selectors.length; i++) {
          var el = document.querySelector(selectors[i]);
          if (el) { el.click(); return true; }
        }
        return false;
      };

      var api = {
        play: function () {
          state.userPaused = false;
          var v = video();
          if (v) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
        },
        pause: function () {
          state.userPaused = true;
          var v = video();
          if (v) v.pause();
        },
        toggle: function () {
          var v = video();
          if (!v) return;
          if (v.paused) api.play(); else api.pause();
        },
        seek: function (t) {
          var v = video();
          if (v) v.currentTime = t;
        },
        next: function () {
          if (!clickFirst(['.player-controls-next-button', 'button.ytp-next-button',
                           'ytm-playlist-panel-video-renderer[selected] + ytm-playlist-panel-video-renderer a'])) {
            var v = video();
            if (v && isFinite(v.duration)) v.currentTime = Math.max(0, v.duration - 0.5);
          }
        },
        previous: function () {
          var v = video();
          if (v && v.currentTime > 3) { v.currentTime = 0; return; }
          if (!clickFirst(['.player-controls-prev-button', 'button.ytp-prev-button'])) {
            history.back();
          }
        },
        setBackground: function (bg) {
          state.background = bg;
          if (bg) api.resumeIfNeeded();
        },
        resumeIfNeeded: function () {
          var v = video();
          if (v && v.paused && !v.ended && !state.userPaused) {
            var p = v.play(); if (p && p.catch) p.catch(function () {});
          }
        },
        report: post
      };
      window.__bgPlay = api;

      // Media events do not bubble, but they can be captured on document.
      ['play', 'playing', 'pause', 'ended', 'loadedmetadata', 'durationchange', 'ratechange', 'seeked']
        .forEach(function (type) {
          document.addEventListener(type, function (e) {
            if (type === 'pause' && state.background && !state.userPaused) {
              // WebKit / YouTube paused us because we went to the background.
              setTimeout(api.resumeIfNeeded, 150);
            }
            if (type === 'play' || type === 'playing') state.userPaused = false;
            post();
          }, true);
        });

      // Taps on the page's own pause button count as a user pause.
      document.addEventListener('click', function () {
        setTimeout(function () {
          var v = video();
          if (v) state.userPaused = v.paused;
        }, 300);
      }, true);

      setInterval(post, 1000);
    })();
    """#
}
