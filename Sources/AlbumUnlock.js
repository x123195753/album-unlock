(function () {
  'use strict';
  // 幂等保护：手动/自动注入都只安装一次
  if (window.__albumUnlockInstalled) return;
  window.__albumUnlockInstalled = true;

  // 相册解锁总开关（原生 App 预置 window.__albumUnlockEnabled）
  var UNLOCK_ON = window.__albumUnlockEnabled !== false;

  var unlockedCount = 0;

  // 提示统一由原生底部气泡渲染（毛玻璃胶囊 + 语义图标），网页内不再自绘，
  // 避免刚打开时同时出现网页 toast 与原生气泡两种风格。

  /* ============ 〇、去边框 + 禁止页面拖动（不强行改色） ============ */

  // 原生预置 window.__albumBeautify（工具箱可开关）
  var BEAUTIFY = window.__albumBeautify !== false;

  var THEME_CSS = [
    /* 禁止拖动/回弹：限制只允许竖向滑动，禁止横向拖拽 */
    'html,body{overscroll-behavior:none !important;overflow-x:hidden !important;',
    'max-width:100% !important;touch-action:pan-y !important;',
    '-webkit-tap-highlight-color:transparent;}',

    /* iframe 及四周容器边框线条去除 */
    'iframe{border:0 !important;outline:none !important;box-shadow:none !important;}',
    '.iframe-box,.iframe-wrap,.iframe-wrapper,.app-frame,.app-box,.app-item,',
    '.app-card,.app-view,.content-box,.main-box{border:0 !important;',
    'outline:none !important;box-shadow:none !important;}',

    /* 网页导航条：原为黑底，改为白底深字与页面协调 */
    '.MuiAppBar-root,.MuiAppBar-positionSticky,.MuiAppBar-positionFixed,.MuiToolbar-root,',
    'header,#header,.header,.page-header,.app-header,.titlebar,.navbar,.nav-bar,',
    '.uni-page-head,.van-nav-bar,.mint-header,.mui-bar-nav,.top-bar{',
    'background:#FFFFFF !important;background-image:none !important;',
    'border:0 !important;box-shadow:0 1px 0 rgba(0,0,0,.06) !important;}',
    '.MuiAppBar-root *,.MuiToolbar-root *,header *,#header *,.header *,.page-header *,',
    '.app-header *,.titlebar *,.navbar *,.nav-bar *,.top-bar *{',
    'color:#1C1C1E !important;fill:#1C1C1E !important;text-shadow:none !important;}',

    /* 输入框只去外发光/描边，不改配色 */
    'input,textarea,select{outline:none !important;}'
  ].join('');

  function installTheme() {
    if (!BEAUTIFY) {
      var old = document.getElementById('__album_theme');
      if (old) old.remove();
      return;
    }
    try {
      if (document.getElementById('__album_theme')) return;
      var st = document.createElement('style');
      st.id = '__album_theme';
      st.textContent = THEME_CSS;
      (document.head || document.documentElement).appendChild(st);
    } catch (e) {}
  }
  installTheme();
  document.addEventListener('DOMContentLoaded', installTheme);
  // 单页应用切换页面时 head 可能重建，兜底补回
  setInterval(installTheme, 3000);

  // 拖动锁：横向拖动直接拦截（竖向滑动不受影响），每个 frame 都会注入本脚本
  function lockDrag(doc) {
    try {
      var sx = 0, sy = 0, tracking = false;
      doc.addEventListener('touchstart', function (e) {
        if (e.touches.length === 1) {
          sx = e.touches[0].clientX; sy = e.touches[0].clientY; tracking = true;
        }
      }, { passive: true });
      doc.addEventListener('touchmove', function (e) {
        if (!tracking || e.touches.length !== 1) return;
        var dx = Math.abs(e.touches[0].clientX - sx);
        var dy = Math.abs(e.touches[0].clientY - sy);
        if (dx > dy && dx > 8) e.preventDefault();
      }, { passive: false });
      doc.addEventListener('touchend', function () { tracking = false; }, { passive: true });
    } catch (err) {}
  }
  lockDrag(document);
  document.addEventListener('DOMContentLoaded', function () { lockDrag(document); });

  /* ============ 一、相册解锁 ============ */

  function unlockInput(input) {
    if (!UNLOCK_ON) return;
    if (!input || input.nodeType !== 1) return;
    if (input.tagName !== 'INPUT' || input.type !== 'file') return;
    if (input.hasAttribute('capture')) {
      input.removeAttribute('capture');
      unlockedCount++;
    }
  }

  function sweep(root) {
    try {
      if (root.nodeType === 1) {
        unlockInput(root);
        if (root.querySelectorAll) {
          var list = root.querySelectorAll('input[type=file]');
          for (var i = 0; i < list.length; i++) unlockInput(list[i]);
        }
      }
    } catch (e) {}
  }

  sweep(document);

  try {
    var mo = new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (m.type === 'attributes') unlockInput(m.target);
        for (var j = 0; j < m.addedNodes.length; j++) sweep(m.addedNodes[j]);
      }
    });
    mo.observe(document.documentElement, {
      childList: true, subtree: true,
      attributes: true, attributeFilter: ['capture']
    });
  } catch (e) {}

  try {
    if (UNLOCK_ON) {
      var origSet = Element.prototype.setAttribute;
      Element.prototype.setAttribute = function (name, value) {
        if (this.tagName === 'INPUT' && String(name).toLowerCase() === 'capture') {
          return;
        }
        return origSet.call(this, name, value);
      };
    }
  } catch (e) {}

  try {
    if (UNLOCK_ON) {
      var desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'capture');
      if (desc && desc.set) {
        Object.defineProperty(HTMLInputElement.prototype, 'capture', {
          configurable: true,
          get: desc.get,
          set: function () { /* 忽略，不写入 capture */ }
        });
      }
    }
  } catch (e) {}

  /* ============ 二、模拟定位 ============ */
  // 坐标由原生 App 通过 window.__albumFakeLocation 预置（GCJ-02）
  window.__setFakeLocation = function (lat, lng, enabled) {
    window.__albumFakeLocation = { enabled: !!enabled, lat: Number(lat), lng: Number(lng) };
    return window.__albumFakeLocation;
  };

  function fakeCoords() {
    var f = window.__albumFakeLocation || { enabled: false, lat: 31.204, lng: 121.588 };
    return {
      latitude: f.lat,
      longitude: f.lng,
      accuracy: 30,
      altitude: null,
      altitudeAccuracy: null,
      heading: null,
      speed: null
    };
  }

  // 2.1 补丁 navigator.geolocation（HTML5 定位）
  try {
    var geo = navigator.geolocation;
    if (geo) {
      ['getCurrentPosition', 'watchPosition'].forEach(function (name) {
        var orig = geo[name] ? geo[name].bind(geo) : null;
        geo[name] = function (success, error, opts) {
          var f = window.__albumFakeLocation;
          if (f && f.enabled) {
            var pos = { coords: fakeCoords(), timestamp: Date.now() };
            setTimeout(function () { try { success(pos); } catch (e) {} }, 30);
            return name === 'watchPosition' ? 1 : undefined;
          }
          return orig ? orig(success, error, opts) : undefined;
        };
      });
    }
  } catch (e) {}

  // 2.1b iframe 定位桥直连（跨域安全版）：
  // 子应用向 parent postMessage({type:'locate-open'})，5 秒内等不到
  // {type:'locate-result-open', data:'<json字符串>'} 回执就报"请求超时"。
  // window.parent 跨域无法 hook（v1.4 失败原因），改为在**每一层 frame**监听消息：
  // 任一 frame 看到 locate-open 且模拟定位开启，直接向发送方 frame 回执模拟坐标。
  // event.source.postMessage 是跨域允许的操作，不依赖门户主框架的 wx 状态机。
  try {
    window.addEventListener('message', function (ev) {
      try {
        var d = ev.data;
        if (!d || d.type !== 'locate-open') return;
        var f = window.__albumFakeLocation;
        if (!f || !f.enabled) return;
        var payload = JSON.stringify({
          errMsg: 'getLocation:ok',
          latitude: Number(f.lat),
          longitude: Number(f.lng),
          accuracy: 30,
          speed: 0
        });
        if (ev.source) {
          ev.source.postMessage({ type: 'locate-result-open', data: payload }, '*');
          console.log('[相册解锁] 定位桥直连：已向子应用回执 ' + f.lat + ',' + f.lng);
        }
      } catch (e) {}
    }, false);
    console.log('[相册解锁] 定位桥直连监听已安装');
  } catch (e) {}

  function isRealWeChat() {
    try { return typeof window.WeixinJSBridge !== 'undefined'; } catch (e) { return false; }
  }

  // 2.2 补丁 wx.getLocation（微信定位），并在非微信容器里模拟 wx.config/ready/error
  function patchWx() {
    if (!window.wx || typeof window.wx !== 'object') return false;
    if (window.wx.__albumPatched) return true;
    var wx = window.wx;

    // 相册：chooseImage 只允许拍照时放开为 相册+拍照（受解锁开关控制）
    if (UNLOCK_ON && typeof wx.chooseImage === 'function' && !wx.__chooseImagePatched) {
      var origChoose = wx.chooseImage;
      wx.chooseImage = function (opts) {
        opts = opts || {};
        var st = opts.sourceType;
        var onlyCamera = !st || (Array.isArray(st) && st.length === 1 && st[0] === 'camera');
        if (onlyCamera) opts.sourceType = ['album', 'camera'];
        return origChoose.call(wx, opts);
      };
      wx.__chooseImagePatched = true;
    }

    var f = window.__albumFakeLocation;
    var fakeOn = f && f.enabled;

    if (fakeOn && !isRealWeChat()) {
      // wx.config：模拟成功，避免页面走 fail 分支禁用功能
      if (typeof wx.config === 'function') {
        wx.config = function (opts) {
          console.log('[相册解锁] wx.config 已模拟成功，appId=', opts && opts.appId);
        };
      }
      // wx.ready：立即执行页面回调（门户会在 ready 里调 getLocation）
      if (typeof wx.ready === 'function') {
        wx.ready = function (fn) { if (typeof fn === 'function') { try { fn(); } catch (e) {} } };
      }
      // wx.error：吞掉失败回调
      wx.error = function () {};

      // wx.getLocation：返回模拟坐标
      wx.getLocation = function (opts) {
        opts = opts || {};
        var res = {
          errMsg: 'getLocation:ok',
          latitude: fakeCoords().latitude,
          longitude: fakeCoords().longitude,
          accuracy: 30,
          speed: 0
        };
        setTimeout(function () {
          if (typeof opts.success === 'function') { try { opts.success(res); } catch (e) {} }
          if (typeof opts.complete === 'function') { try { opts.complete(res); } catch (e) {} }
        }, 30);
      };

      console.log('[相册解锁] 定位模拟已开启: ' + f.lat + ',' + f.lng);
    }

    wx.__albumPatched = true;
    return true;
  }

  // 捕获 wx 的赋值：页面动态加载 jweixin 时立即补丁（所有 frame 均执行）
  try {
    var __wxValue = window.wx;
    Object.defineProperty(window, 'wx', {
      configurable: true,
      get: function () { return __wxValue; },
      set: function (v) { __wxValue = v; patchWx(); }
    });
  } catch (e) {}

  patchWx();
  var tries = 0;
  var timer = setInterval(function () {
    if (patchWx() || ++tries > 60) clearInterval(timer);
  }, 500);

  // 3. 状态查询
  window.__albumUnlockStats = function () {
    var f = window.__albumFakeLocation || {};
    return {
      unlocked: unlockedCount,
      wxPatched: !!(window.wx && window.wx.__albumPatched),
      fakeLocation: f.enabled ? (f.lat + ',' + f.lng) : 'off'
    };
  };

  // 就绪提示不再由网页弹出：原生在首个 didFinish 统一发一条（含定位状态）
})();
