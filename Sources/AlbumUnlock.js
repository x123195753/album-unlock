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

  // 导航条颜色：可由工具箱调色盘动态修改（原生预置 window.__albumNavColor）
  var NAV_DEFAULT = '#F0F4F8';

  function buildCSS() {
    var nav = window.__albumNavColor || NAV_DEFAULT;
    return [
    /* 禁止拖动/回弹：限制只允许竖向滑动，禁止横向拖拽 */
    'html,body{overscroll-behavior:none !important;overflow-x:hidden !important;',
    'max-width:100% !important;touch-action:pan-y !important;',
    '-webkit-tap-highlight-color:transparent;}',

    /* iframe 及四周容器边框线条去除 */
    'iframe{border:0 !important;outline:none !important;box-shadow:none !important;}',
    '.iframe-box,.iframe-wrap,.iframe-wrapper,.app-frame,.app-box,.app-item,',
    '.app-card,.app-view,.content-box,.main-box{border:0 !important;',
    'outline:none !important;box-shadow:none !important;}',

    /* 网页导航条：底色由调色盘控制，深色文字 */
    '.MuiAppBar-root,.MuiAppBar-positionSticky,.MuiAppBar-positionFixed,.MuiToolbar-root,',
    'header,#header,.header,.page-header,.app-header,.titlebar,.navbar,.nav-bar,',
    '.uni-page-head,.van-nav-bar,.mint-header,.mui-bar-nav,.top-bar{',
    'background:' + nav + ' !important;background-image:none !important;',
    'border:0 !important;box-shadow:none !important;}',
    '.MuiAppBar-root *,.MuiToolbar-root *,header *,#header *,.header *,.page-header *,',
    '.app-header *,.titlebar *,.navbar *,.nav-bar *,.top-bar *{',
    'color:#1C1C1E !important;fill:#1C1C1E !important;text-shadow:none !important;}',

    /* 导航栏压矮：MUI Toolbar 默认 56px → 40px，标题字号同步缩小 */
    '.MuiToolbar-root{min-height:40px !important;height:40px !important;',
    'padding-top:0 !important;padding-bottom:0 !important;}',
    '.MuiToolbar-root .MuiTypography-h6{font-size:16px !important;}',
    '.MuiToolbar-root .MuiIconButton-root{padding:6px !important;}',

    /* 输入框只去外发光/描边，不改配色 */
    'input,textarea,select{outline:none !important;}'
    ].join('');
  }

  function installTheme() {
    if (!BEAUTIFY) {
      var old = document.getElementById('__album_theme');
      if (old) old.remove();
      return;
    }
    try {
      var st = document.getElementById('__album_theme');
      if (!st) {
        st = document.createElement('style');
        st.id = '__album_theme';
        (document.head || document.documentElement).appendChild(st);
      }
      st.textContent = buildCSS();
    } catch (e) {}
  }
  // 供原生调色盘调用：换色即时生效，无需刷新页面
  window.__albumSetNavColor = function (hex) {
    window.__albumNavColor = hex;
    installTheme();
  };
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

  /* ============ 三、上传图片注入 EXIF（拍摄时间 + GPS，与模拟定位一致） ============ */

  function exifOn() { return window.__albumExifEnabled !== false; }

  // 构造 EXIF APP1 段（大端 TIFF）：机型/DateTime + ExifIFD(拍摄时间/像素尺寸) + GPSIFD
  function buildExifApp1(lat, lng, width, height) {
    try {
      var now = new Date();
      function p2(n) { return n < 10 ? '0' + n : '' + n; }
      var dateStr = now.getFullYear() + ':' + p2(now.getMonth() + 1) + ':' + p2(now.getDate()) + ' ' +
        p2(now.getHours()) + ':' + p2(now.getMinutes()) + ':' + p2(now.getSeconds());
      var dateStamp = now.getFullYear() + ':' + p2(now.getMonth() + 1) + ':' + p2(now.getDate());

      function u32b(v) { return [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255]; }
      function u16b(v) { return [(v >> 8) & 255, v & 255]; }
      function ascii(s) { var a = []; for (var i = 0; i < s.length; i++) a.push(s.charCodeAt(i) & 255); a.push(0); return a; }
      function dms(v) {
        var d = Math.floor(Math.abs(v)), mf = (Math.abs(v) - d) * 60, m = Math.floor(mf);
        var s = Math.min(Math.round((mf - m) * 60 * 100), 5999);
        return [[d, 1], [m, 1], [s, 100]];
      }
      function rats(a) { var b = []; for (var i = 0; i < a.length; i++) b = b.concat(u32b(a[i][0]), u32b(a[i][1])); return b; }

      var hasGPS = lat !== null && lng !== null && isFinite(lat) && isFinite(lng);
      var la = hasGPS ? dms(lat) : null;
      var lo = hasGPS ? dms(lng) : null;

      // 条目：[tag, type, valueBytes]；type: 1 BYTE, 2 ASCII, 4 LONG, 5 RATIONAL
      var ifd0 = [
        [0x010F, 2, ascii('Apple')],              // Make
        [0x0110, 2, ascii('iPhone')],             // Model（机型适配）
        [0x0132, 2, ascii(dateStr)],              // DateTime
        [0x8769, 4, null, 'E'],                   // ExifIFD 指针
        [0x8825, 4, null, 'G']                    // GPS IFD 指针
      ];
      var exif = [
        [0x9003, 2, ascii(dateStr)],              // DateTimeOriginal
        [0x9004, 2, ascii(dateStr)],              // DateTimeDigitized
        [0xA002, 4, u32b(width | 0)],             // PixelXDimension
        [0xA003, 4, u32b(height | 0)]             // PixelYDimension
      ];
      var gps = null;
      if (hasGPS) {
        gps = [
          [0x0000, 1, [2, 3, 0, 0]],                          // GPSVersionID
          [0x0001, 2, [lat >= 0 ? 78 : 83, 0]],               // N/S
          [0x0002, 5, rats(la)],                              // GPSLatitude
          [0x0003, 2, [lng >= 0 ? 69 : 87, 0]],               // E/W
          [0x0004, 5, rats(lo)],                              // GPSLongitude
          [0x0007, 5, rats([[now.getUTCHours(), 1], [now.getUTCMinutes(), 1], [now.getUTCSeconds(), 1]])],
          [0x0012, 2, ascii('GCJ-02')],                       // MapDatum
          [0x001D, 2, ascii(dateStamp)]                       // GPSDateStamp
        ];
      } else {
        ifd0 = ifd0.slice(0, 4);
      }

      function ifdSize(n) { return 2 + 12 * n + 4; }
      var off0 = 8;
      var offE = off0 + ifdSize(ifd0.length);
      var offG = offE + ifdSize(exif.length);
      var dataStart = offG + (gps ? ifdSize(gps.length) : 0);

      var data = [];
      function fillValue(e, ptrName) {
        if (ptrName === 'E') return u32b(offE);
        if (ptrName === 'G') return u32b(offG);
        var b = e[2];
        if (b.length > 4) {
          e.__off = dataStart + data.length;
          data.push.apply(data, b);
          if (b.length % 2) data.push(0);
          return null;
        }
        var inl = b.slice();
        while (inl.length < 4) inl.push(0);
        return inl;
      }
      function serialize(entries) {
        var out = u16b(entries.length);
        for (var i = 0; i < entries.length; i++) {
          var e = entries[i];
          var tag = e[0], type = e[1], val = fillValue(e, e[3]);
          var count = type === 2 ? e[2].length : (type === 5 ? e[2].length / 8 : (type === 1 ? 4 : 1));
          out = out.concat(u16b(tag), u16b(type), u32b(count));
          out = out.concat(val === null ? u32b(e.__off) : val);
        }
        out = out.concat(u32b(0)); // 下一 IFD 偏移 = 0
        return out;
      }

      var tiff = [0x4D, 0x4D, 0x00, 0x2A].concat(u32b(8))  // "MM" + 0x2A + IFD0 偏移 8
        .concat(serialize(ifd0))
        .concat(serialize(exif));
      if (gps) tiff = tiff.concat(serialize(gps));
      tiff = tiff.concat(data);

      // APP1 段：FF E1 + 长度 + "Exif\0\0" + TIFF
      var payload = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00].concat(tiff);
      var segLen = payload.length + 2;
      return new Uint8Array([0xFF, 0xE1].concat(u16b(segLen)).concat(payload));
    } catch (e) { return null; }
  }

  // 把 APP1 写进 JPEG（替换已有 Exif 段，避免带上照片原始的真实 GPS）
  function injectExif(buffer, app1) {
    try {
      var u8 = new Uint8Array(buffer);
      if (u8.length < 4 || u8[0] !== 0xFF || u8[1] !== 0xD8 || !app1) return null;
      var segs = [], insertPos = 2, pos = 2, remove = [];
      while (pos + 4 <= u8.length) {
        if (u8[pos] !== 0xFF) break;
        var m = u8[pos + 1];
        if (m === 0xD9 || m === 0xDA) { segs.push([pos, u8.length]); break; } // 扫描数据 → 余下全部
        if (m >= 0xD0 && m <= 0xD7) { pos += 2; continue; }                   // 独立标记
        var segLen = (u8[pos + 2] << 8) | u8[pos + 3];
        var end = pos + 2 + segLen;
        if (m === 0xE0) { insertPos = end; }
        if (m === 0xE1 && u8[pos + 4] === 0x45 && u8[pos + 5] === 0x78 && u8[pos + 6] === 0x69 &&
            u8[pos + 7] === 0x66 && u8[pos + 8] === 0x00) { remove.push([pos, end]); }
        else { segs.push([pos, end]); }
        pos = end;
      }
      if (!segs.length) segs.push([2, u8.length]);
      var total = insertPos + app1.length;
      for (var i = 0; i < segs.length; i++) { if (segs[i][0] >= insertPos || segs[i][1] > insertPos) total += segs[i][1] - segs[i][0]; }
      var out = new Uint8Array(total), w = 0;
      out.set(u8.subarray(0, insertPos), 0); w = insertPos;
      out.set(app1, w); w += app1.length;
      for (var j = 0; j < segs.length; j++) {
        if (segs[j][1] <= insertPos) continue;
        out.set(u8.subarray(segs[j][0], segs[j][1]), w); w += segs[j][1] - segs[j][0];
      }
      return out.subarray(0, w);
    } catch (e) { return null; }
  }

  var exifDoneFiles = typeof WeakSet === 'function' ? new WeakSet() : null;

  // 需要处理的图片（JPEG/PNG/WebP/HEIC 都会被统一重编码为 JPEG 并注入 EXIF）
  function isImage(file) {
    if (!file) return false;
    return /^image\//i.test(file.type) || /\.(jpe?g|png|webp|heic|heif)$/i.test(file.name || '');
  }

  // 分辨率适配机型：最长边重采样到 4032px（iPhone 12MP 主摄规格），补齐或压缩到同一规格
  function normalizeResolution(file, cb) {
    try {
      var img = new Image();
      var url = URL.createObjectURL(file);
      var fail = function () { URL.revokeObjectURL(url); cb(file); };
      img.onerror = fail;
      img.onload = function () {
        try {
          var MAX = 4032;
          var w = img.naturalWidth || img.width, h = img.naturalHeight || img.height;
          if (!w || !h) { fail(); return; }
          var scale = MAX / Math.max(w, h);
          var w2 = Math.max(1, Math.round(w * scale)), h2 = Math.max(1, Math.round(h * scale));
          var cv = document.createElement('canvas');
          cv.width = w2; cv.height = h2;
          var ctx = cv.getContext('2d');
          ctx.imageSmoothingEnabled = true;
          ctx.imageSmoothingQuality = 'high';
          ctx.drawImage(img, 0, 0, w2, h2);
          URL.revokeObjectURL(url);
          cv.toBlob(function (blob) {
            if (!blob) { cb(file); return; }
            var nf = new File([blob], (file.name || 'photo').replace(/\.(png|webp|heic)$/i, '.jpg'),
                              { type: 'image/jpeg' });
            nf.__albumDims = [w2, h2];
            if (exifDoneFiles) exifDoneFiles.add(nf);
            cb(nf);
          }, 'image/jpeg', 0.92);
        } catch (e) { fail(); }
      };
      img.src = url;
    } catch (e) { cb(file); }
  }

  // 处理单个文件：分辨率归一化 → 注入 EXIF → 生成新 File
  function injectFile(file, cb) {
    normalizeResolution(file, function (resized) {
      var fr = new FileReader();
      fr.onload = function () {
        var f = window.__albumFakeLocation;
        var dims = resized.__albumDims || [0, 0];
        var app1 = buildExifApp1(f && f.enabled ? f.lat : null, f && f.enabled ? f.lng : null,
                                 dims[0], dims[1]);
        var out = injectExif(fr.result, app1);
        if (!out) { cb(resized); return; }
        try {
          var nf = new File([out], resized.name, { type: resized.type || 'image/jpeg' });
          if (exifDoneFiles) exifDoneFiles.add(nf);
          cb(nf);
        } catch (e) { cb(resized); }
      };
      fr.onerror = function () { cb(resized); };
      fr.readAsArrayBuffer(resized);
    });
  }

  // 批量替换 input.files（保持顺序，非 JPEG 原样保留）
  function processInput(input, done) {
    var files = [];
    try { files = Array.prototype.slice.call(input.files || []); } catch (e) {}
    var jobs = [];
    for (var i = 0; i < files.length; i++) {
      if (isImage(files[i]) && !(exifDoneFiles && exifDoneFiles.has(files[i]))) jobs.push(i);
    }
    if (!jobs.length) { done(); return; }
    var pending = jobs.length, changed = false;
    for (var k = 0; k < jobs.length; k++) {
      (function (idx) {
        injectFile(files[idx], function (nf) {
          if (nf !== files[idx]) { files[idx] = nf; changed = true; }
          if (--pending === 0) {
            if (changed) {
              try {
                var dt = new DataTransfer();
                for (var m = 0; m < files.length; m++) dt.items.add(files[m]);
                input.files = dt.files;
              } catch (e) {}
            }
            done();
          }
        });
      })(jobs[k]);
    }
  }

  // change 事件先拦截：EXIF 处理完再放行给页面，页面拿到的已是带元数据的图
  document.addEventListener('change', function (e) {
    if (e.__albumExifDone) return;
    var t = e.target;
    if (!t || t.tagName !== 'INPUT' || t.type !== 'file' || !t.files || !t.files.length) return;
    var f = window.__albumFakeLocation;
    if (!exifOn()) return;
    var hasImg = false;
    for (var i = 0; i < t.files.length; i++) { if (isImage(t.files[i]) && !(exifDoneFiles && exifDoneFiles.has(t.files[i]))) { hasImg = true; break; } }
    if (!hasImg) return;
    e.stopImmediatePropagation();
    e.stopPropagation();
    processInput(t, function () {
      var ev = new Event('change', { bubbles: true });
      ev.__albumExifDone = true;
      t.dispatchEvent(ev);
    });
  }, true);

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
