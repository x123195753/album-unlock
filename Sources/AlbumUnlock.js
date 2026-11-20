(function () {
  'use strict';
  // 幂等保护：手动/自动注入都只安装一次
  if (window.__albumUnlockInstalled) return;
  window.__albumUnlockInstalled = true;

  var unlockedCount = 0;

  function toast(msg) {
    try {
      var d = document.createElement('div');
      d.textContent = msg;
      d.style.cssText = 'position:fixed;left:50%;bottom:80px;transform:translateX(-50%);' +
        'z-index:2147483647;background:rgba(0,0,0,.75);color:#fff;padding:8px 14px;' +
        'border-radius:8px;font-size:13px;pointer-events:none;transition:opacity .4s;';
      document.body.appendChild(d);
      setTimeout(function () { d.style.opacity = '0'; }, 1800);
      setTimeout(function () { d.remove(); }, 2400);
    } catch (e) {}
  }

  /* ============ 一、相册解锁 ============ */

  function unlockInput(input) {
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
    var origSet = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      if (this.tagName === 'INPUT' && String(name).toLowerCase() === 'capture') {
        return;
      }
      return origSet.call(this, name, value);
    };
  } catch (e) {}

  try {
    var desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'capture');
    if (desc && desc.set) {
      Object.defineProperty(HTMLInputElement.prototype, 'capture', {
        configurable: true,
        get: desc.get,
        set: function () { /* 忽略，不写入 capture */ }
      });
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

  // 2.1b iframe 定位桥直连：子应用向 parent 发 locate-open 时，本地直接合成回执，
  //      不依赖门户主框架的 wx 状态机（规避 5 秒超时）
  if (window.parent !== window) {
    try {
      var origParentPost = window.parent.postMessage.bind(window.parent);
      window.parent.postMessage = function (msg, targetOrigin, transfer) {
        try {
          if (msg && msg.type === 'locate-open') {
            var f = window.__albumFakeLocation;
            if (f && f.enabled) {
              var payload = JSON.stringify({
                errMsg: 'getLocation:ok',
                latitude: Number(f.lat),
                longitude: Number(f.lng),
                accuracy: 30,
                speed: 0
              });
              setTimeout(function () {
                try {
                  var ev = new MessageEvent('message', {
                    data: { type: 'locate-result-open', data: payload }
                  });
                  window.dispatchEvent(ev);
                } catch (e) {}
              }, 100);
              console.log('[相册解锁] 定位桥直连：已本地回执 ' + f.lat + ',' + f.lng);
            }
          }
        } catch (e) {}
        return origParentPost(msg, targetOrigin, transfer);
      };
      console.log('[相册解锁] iframe 定位桥直连已安装');
    } catch (e) {}
  }

  function isRealWeChat() {
    try { return typeof window.WeixinJSBridge !== 'undefined'; } catch (e) { return false; }
  }

  // 2.2 补丁 wx.getLocation（微信定位），并在非微信容器里模拟 wx.config/ready/error
  function patchWx() {
    if (!window.wx || typeof window.wx !== 'object') return false;
    if (window.wx.__albumPatched) return true;
    var wx = window.wx;

    // 相册：chooseImage 只允许拍照时放开为 相册+拍照（真实微信环境同样生效）
    if (typeof wx.chooseImage === 'function' && !wx.__chooseImagePatched) {
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

  function readyToast() {
    var f = window.__albumFakeLocation;
    var msg = '相册解锁已就绪';
    if (f && f.enabled) msg += '（定位模拟 ' + Number(f.lat).toFixed(4) + ',' + Number(f.lng).toFixed(4) + '）';
    toast(msg);
  }
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(readyToast, 600);
  } else {
    window.addEventListener('DOMContentLoaded', function () { setTimeout(readyToast, 600); });
  }
})();
