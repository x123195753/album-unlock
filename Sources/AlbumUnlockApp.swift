import SwiftUI
import WebKit
import CoreLocation

@main
struct AlbumUnlockApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 模拟定位设置

struct LocationSettings: Codable, Equatable {
    /// "off" = 关闭 | "device" = 手机真实定位 | "manual" = 手动坐标
    /// nil 兼容旧版本保存的数据（视为手动模式）
    var mode: String?
    var enabled: Bool
    var lat: Double
    var lng: Double

    var effectiveMode: String { mode ?? "manual" }

    static let defaultsKey = "fakeLocationSettings"
    static let deviceCacheKey = "lastDeviceGCJLocation"

    static func load() -> LocationSettings {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode(LocationSettings.self, from: data) {
            return s
        }
        // 默认：手机真实定位模式
        return LocationSettings(mode: "device", enabled: true, lat: 31.2989, lng: 120.5853)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// 缓存最近一次手机定位（GCJ-02），页面加载时先用它，随后刷新为最新
    static func cacheDevice(lat: Double, lng: Double) {
        UserDefaults.standard.set("\(lat),\(lng)", forKey: deviceCacheKey)
    }

    static func cachedDevice() -> (lat: Double, lng: Double)? {
        guard let s = UserDefaults.standard.string(forKey: deviceCacheKey) else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0) }
        guard p.count == 2 else { return nil }
        return (p[0], p[1])
    }

    var preludeScript: String {
        switch effectiveMode {
        case "off":
            return "window.__albumFakeLocation = {enabled: false, lat: \(lat), lng: \(lng)};"
        case "device":
            if let c = LocationSettings.cachedDevice() {
                return "window.__albumFakeLocation = {enabled: true, lat: \(c.lat), lng: \(c.lng)};"
            }
            return "window.__albumFakeLocation = {enabled: false, lat: \(lat), lng: \(lng)};"
        default:
            return "window.__albumFakeLocation = {enabled: \(enabled), lat: \(lat), lng: \(lng)};"
        }
    }
}

struct LocationSettingsView: View {
    @Binding var settings: LocationSettings
    var onApply: (LocationSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode: String
    @State private var enabled: Bool
    @State private var latText: String
    @State private var lngText: String
    @State private var deviceCoord = ""
    @State private var deviceStatus = ""
    @State private var deviceLat: Double?
    @State private var deviceLng: Double?
    @State private var fetching = false
    @State private var errorText = ""

    // 常用预设（GCJ-02 坐标）
    private let presets: [(name: String, lat: Double, lng: Double)] = [
        ("苏州（沙钢本地）", 31.2989, 120.5853),
        ("上海人民广场", 31.2335, 121.4692),
        ("上海张江", 31.2040, 121.5880),
        ("南京新街口", 32.0415, 118.7785)
    ]

    init(settings: Binding<LocationSettings>, onApply: @escaping (LocationSettings) -> Void) {
        _settings = settings
        self.onApply = onApply
        _mode = State(initialValue: settings.wrappedValue.effectiveMode)
        _enabled = State(initialValue: settings.wrappedValue.enabled)
        _latText = State(initialValue: String(format: "%.6f", settings.wrappedValue.lat))
        _lngText = State(initialValue: String(format: "%.6f", settings.wrappedValue.lng))
        if let c = LocationSettings.cachedDevice() {
            _deviceCoord = State(initialValue: String(format: "%.6f, %.6f", c.lng, c.lat))
            _deviceLat = State(initialValue: c.lat)
            _deviceLng = State(initialValue: c.lng)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("定位方式")) {
                    Picker("模式", selection: $mode) {
                        Text("手机真实定位").tag("device")
                        Text("手动坐标").tag("manual")
                        Text("关闭").tag("off")
                    }
                    .pickerStyle(.segmented)

                    if mode == "device" {
                        Text("页面请求定位时自动返回手机当前位置（已自动转换为 GCJ-02 坐标，无需手填）。每次打开页面会自动刷新。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("当前定位")
                            Spacer()
                            Text(deviceCoord.isEmpty ? "未获取" : deviceCoord)
                                .foregroundColor(.secondary)
                        }
                        Button(fetching ? "定位中…" : "立即刷新定位") { fetchDevice() }
                            .disabled(fetching)
                        if !deviceStatus.isEmpty {
                            Text(deviceStatus)
                                .font(.caption)
                                .foregroundColor(deviceStatus.contains("失败") || deviceStatus.contains("拒绝") ? .red : .secondary)
                        }
                    }

                    if mode == "manual" {
                        Toggle("启用定位模拟", isOn: $enabled)
                        HStack {
                            Text("纬度").frame(width: 44, alignment: .leading)
                            TextField("31.298900", text: $latText)
                                .keyboardType(.decimalPad)
                        }
                        HStack {
                            Text("经度").frame(width: 44, alignment: .leading)
                            TextField("120.585300", text: $lngText)
                                .keyboardType(.decimalPad)
                        }
                        Text("坐标请使用 GCJ-02 火星坐标系（高德/腾讯地图拾取坐标器可获取），否则页面上地图会偏移约 500 米。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if mode == "off" {
                        Text("关闭后页面定位请求不再由本 App 接管。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if !errorText.isEmpty {
                        Text(errorText).font(.caption).foregroundColor(.red)
                    }
                }

                if mode == "manual" {
                    Section(header: Text("常用位置预设")) {
                        ForEach(presets, id: \.name) { p in
                            Button {
                                latText = String(format: "%.6f", p.lat)
                                lngText = String(format: "%.6f", p.lng)
                                enabled = true
                            } label: {
                                HStack {
                                    Text(p.name)
                                    Spacer()
                                    Text("\(String(format: "%.4f", p.lat)), \(String(format: "%.4f", p.lng))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("保存并应用到当前页面") { apply() }
                }
            }
            .navigationTitle("定位设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func fetchDevice() {
        fetching = true
        deviceStatus = ""
        DeviceLocator.shared.fetch { lat, lng, err in
            DispatchQueue.main.async {
                fetching = false
                if let err = err {
                    deviceStatus = err
                    return
                }
                deviceLat = lat
                deviceLng = lng
                deviceCoord = String(format: "%.6f, %.6f", lng, lat)
                deviceStatus = "获取成功（GCJ-02）"
            }
        }
    }

    private func apply() {
        var lat = settings.lat
        var lng = settings.lng
        if mode == "manual" {
            guard let l = Double(latText), let g = Double(lngText),
                  l >= -90, l <= 90, g >= -180, g <= 180 else {
                errorText = "经纬度格式不正确（纬度 -90~90，经度 -180~180）"
                return
            }
            lat = l
            lng = g
        } else if mode == "device" {
            if let dl = deviceLat, let dg = deviceLng {
                lat = dl
                lng = dg
            } else if let c = LocationSettings.cachedDevice() {
                lat = c.lat
                lng = c.lng
            } else {
                errorText = "尚未获取到手机定位，请先点「立即刷新定位」"
                return
            }
        }
        errorText = ""
        let s = LocationSettings(mode: mode, enabled: mode == "manual" ? enabled : true, lat: lat, lng: lng)
        s.save()
        if mode == "device" { LocationSettings.cacheDevice(lat: lat, lng: lng) }
        settings = s
        onApply(s)
        dismiss()
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var core = WebCore()
    @State private var urlField = "http://qypt.shasteel.cn/mobile-apps/open"
    @State private var showLocationSheet = false
    @State private var showToolSheet = false
    @State private var locationSettings: LocationSettings = .load()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部地址栏
            HStack(spacing: 8) {
                Button {
                    core.webView.goBack()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                }
                .disabled(!core.canGoBack)
                .frame(width: 28)

                Button {
                    core.webView.goForward()
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 17, weight: .semibold))
                }
                .disabled(!core.canGoForward)
                .frame(width: 28)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("输入网址", text: $urlField)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.footnote)
                        .submitLabel(.go)
                        .onSubmit { goToURL() }
                    Button {
                        core.webView.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button("前往") { goToURL() }
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if !core.statusLine.isEmpty {
                HStack {
                    Spacer()
                    Text(core.statusLine)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            BrowserView(core: core)
                // 关键：关闭 SwiftUI 的键盘自动避让，由 WebKit 内部滚动输入框到键盘上方。
                // 否则双重避让会让第三方键盘（讯飞/搜狗）的工具条与键盘脱节、页面出现空隙。
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .bottomTrailing) {
            // 悬浮工具按钮（右下角）
            Button {
                showToolSheet = true
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.blue))
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 44)
        }
        .onAppear {
            core.load(urlField)
            core.refreshDeviceLocation()
        }
        .sheet(isPresented: $showLocationSheet) {
            LocationSettingsView(settings: $locationSettings) { newSettings in
                locationSettings = newSettings
                core.applyLocationSettings(newSettings)
            }
        }
        .sheet(isPresented: $showToolSheet) {
            ToolMenuView(core: core) {
                showToolSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showLocationSheet = true }
            }
        }
    }

    /// 统一处理"前往"：补协议、去空白后加载（修复原按钮无效问题）
    private func goToURL() {
        var s = urlField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "http://" + s }
        if let url = URL(string: s) {
            urlField = s
            core.load(s)
        } else {
            core.showToast("网址格式不正确")
        }
    }
}

// MARK: - 悬浮工具菜单

struct ToolMenuView: View {
    @ObservedObject var core: WebCore
    var onOpenLocation: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("相册解锁")) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { core.runUnlock() }
                    } label: {
                        Label("解锁相册（恢复拍照/相册选择菜单）", systemImage: "lock.open")
                    }
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { core.scanFileInputs() }
                    } label: {
                        Label("扫描文件框（查看上传框解锁状态）", systemImage: "doc.text.magnifyingglass")
                    }
                }
                Section(header: Text("定位")) {
                    Button {
                        onOpenLocation()
                    } label: {
                        Label("定位设置（手机定位 / 手动坐标）", systemImage: "location")
                    }
                }
                Section(header: Text("排查")) {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { core.dumpDebugInfo() }
                    } label: {
                        Label("调试（导出凭据与子应用地址）", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    Button {
                        dismiss()
                        core.webView.reload()
                    } label: {
                        Label("重新加载页面", systemImage: "arrow.clockwise")
                    }
                }
                Section(header: Text("维护"), footer: Text("清除缓存会同时清除登录状态，需要重新登录门户。")) {
                    Button(role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { core.clearAllCache() }
                    } label: {
                        Label("清除所有缓存（将退出登录）", systemImage: "trash")
                    }
                }
                Section(header: Text("当前状态")) {
                    let s = core.quickStats
                    Text(s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("工具箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - WebView 核心

final class WebCore: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var statusLine = ""
    @Published var quickStats = "尚未加载页面"

    private var observers: [NSKeyValueObservation] = []
    private var locationSettings: LocationSettings = .load()

    override init() {
        let cfg = WKWebViewConfiguration()
        let controller = cfg.userContentController
        // 预置脚本：先写入定位模拟参数（所有 frame、文档开始时）
        let settings = LocationSettings.load()
        let prelude = WKUserScript(
            source: settings.preludeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        controller.addUserScript(prelude)
        // 主解锁脚本：相册解锁 + wx/geolocation 定位补丁
        let script = WKUserScript(
            source: AlbumUnlockScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false, // 注入所有 frame，包括门户 iframe 里的子应用
            in: .page
        )
        controller.addUserScript(script)
        // UA 追加 MicroMessenger 标识，让按微信环境做校验的页面放行
        cfg.applicationNameForUserAgent = "MicroMessenger/8.0.49"
        webView = WKWebView(frame: .zero, configuration: cfg)

        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self

        observers.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in
            self?.canGoBack = w.canGoBack
        })
        observers.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in
            self?.canGoForward = w.canGoForward
        })
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] w, _ in
            self?.statusLine = w.url?.host ?? ""
        })
    }

    func load(_ urlString: String) {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty, !s.lowercased().hasPrefix("http") { s = "http://" + s }
        guard let url = URL(string: s) else { return }
        webView.load(URLRequest(url: url))
    }

    /// 更新定位设置：写回 UserDefaults、重建注入脚本，并对当前主 frame 立即生效
    func applyLocationSettings(_ s: LocationSettings) {
        locationSettings = s
        rebuildScripts()

        if s.effectiveMode == "device" {
            // 手机真实定位：拉取当前位置（成功后自动同步到页面并刷新）
            refreshDeviceLocation(force: true, reloadAfter: true)
            statusLine = "📱 正在获取手机定位…"
            return
        }

        // 手动/关闭模式：当前页立即生效；整页刷新让 iframe 子应用同步
        let js = """
        (function(){
          window.__albumFakeLocation = {enabled: \(s.effectiveMode == "manual" && s.enabled), lat: \(s.lat), lng: \(s.lng)};
          if (window.__albumUnlockInstalled) { location.reload(); }
          return 'applied';
        })()
        """
        webView.evaluateJavaScript(js) { _, _ in }
        statusLine = s.effectiveMode == "manual" && s.enabled
            ? "📍 \(String(format: "%.4f", s.lat)),\(String(format: "%.4f", s.lng))"
            : "定位模拟已关闭"
        quickStats = statusLine
    }

    /// 重建预置脚本（定位设置变化后调用，保证后续导航带上新参数）
    private func rebuildScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: locationSettings.preludeScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        controller.addUserScript(WKUserScript(
            source: AlbumUnlockScript.source,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }

    // MARK: 手机真实定位

    private var lastDeviceFetchAt = Date.distantPast

    /// 手机定位模式下：取当前位置（WGS-84 → GCJ-02），写入缓存并同步到当前页面。
    /// 每次页面导航时自动调用（30 秒节流），移动中也能拿到最新位置。
    func refreshDeviceLocation(force: Bool = false, reloadAfter: Bool = false) {
        guard locationSettings.effectiveMode == "device" else { return }
        if !force, Date().timeIntervalSince(lastDeviceFetchAt) < 30 { return }
        lastDeviceFetchAt = Date()
        DeviceLocator.shared.fetch { [weak self] lat, lng, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { self.statusLine = "📱定位失败: \(error)" }
                return
            }
            LocationSettings.cacheDevice(lat: lat, lng: lng)
            DispatchQueue.main.async {
                self.locationSettings.mode = "device"
                self.locationSettings.lat = lat
                self.locationSettings.lng = lng
                self.locationSettings.save()
                self.rebuildScripts()
                let js = "window.__albumFakeLocation = {enabled: true, lat: \(lat), lng: \(lng)};"
                self.webView.evaluateJavaScript(js) { _, _ in
                    if reloadAfter { self.webView.reload() }
                }
                self.statusLine = "📱 \(String(format: "%.4f", lat)),\(String(format: "%.4f", lng))"
                self.quickStats = "📱 手机定位 \(String(format: "%.4f", lat)),\(String(format: "%.4f", lng))"
            }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // 每次页面开始加载时刷新手机定位（节流），确保坐标随人移动更新
        refreshDeviceLocation()
    }

    /// 手动再执行一次解锁脚本（幂等，用于动态页面兜底）
    func runUnlock() {
        let js = """
        (function(){
          if (!window.__albumUnlockInstalled) { return '脚本未安装'; }
          var n = 0;
          document.querySelectorAll('input[type=file][capture]').forEach(function(i){
            i.removeAttribute('capture'); n++;
          });
          var s = window.__albumUnlockStats ? window.__albumUnlockStats() : {};
          return '本次解锁:' + n + ' wx:' + (s.wxPatched ? 'ok' : 'n/a') +
                 ' 定位:' + (s.fakeLocation || 'off');
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                let text = (result as? String) ?? "脚本未就绪"
                self?.statusLine = text
                self?.quickStats = text
            }
        }
    }

    /// 应用内轻提示
    func showToast(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 清除全部网站数据（缓存/Cookie/localStorage 等），会丢失登录态
    func clearAllCache() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types,
                                                modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            DispatchQueue.main.async {
                self?.webView.reload()
                self?.statusLine = "已清除全部缓存"
                self?.quickStats = "已清除全部缓存（已退出登录）"
            }
        }
    }

    /// 加载失败时弹窗显示原因，便于排查
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let alert = UIAlertController(title: "页面加载失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        let alert = UIAlertController(title: "页面加载出错", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        UIApplication.topViewController()?.present(alert, animated: true)
    }

    /// 导出登录凭据与 iframe 子应用地址，用于远程排查
    func dumpDebugInfo() {
        let js = """
        (function(){
          var out = [];
          try {
            var ud = localStorage.getItem('UserData');
            out.push('USERDATA=' + (ud || 'none'));
          } catch(e) { out.push('USERDATA_ERR=' + e); }
          try {
            var ifr = document.querySelectorAll('iframe');
            for (var i = 0; i < ifr.length; i++) out.push('IFRAME' + i + '=' + ifr[i].src);
          } catch(e) { out.push('IFRAME_ERR=' + e); }
          out.push('TOPURL=' + location.href);
          return out.join('\\n');
        })()
        """
        webView.evaluateJavaScript(js) { result, _ in
            let text = (result as? String) ?? "获取失败"
            let alert = UIAlertController(title: "调试信息（截图发我）", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好的", style: .default))
            UIApplication.topViewController()?.present(alert, animated: true)
        }
    }

    /// 列出页面上所有 file input 状态，方便排查
    func scanFileInputs() {
        let js = """
        (function(){
          var out = [];
          document.querySelectorAll('input[type=file]').forEach(function(i){
            out.push((i.hasAttribute('capture') ? '[仍有capture]' : '[已解锁]') + (i.accept ? ' accept=' + i.accept : ''));
          });
          return out.length ? out.join('\\n') : '本页面没有 file input（可能在 iframe 内，脚本已自动覆盖）';
        })()
        """
        webView.evaluateJavaScript(js) { result, _ in
            let text = (result as? String) ?? "扫描失败"
            let alert = UIAlertController(title: "文件上传框状态", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好的", style: .default))
            UIApplication.topViewController()?.present(alert, animated: true)
        }
    }
}

// MARK: - 手机真实定位器（CoreLocation + WGS-84 → GCJ-02 火星坐标转换）

final class DeviceLocator: NSObject, CLLocationManagerDelegate {
    static let shared = DeviceLocator()

    private let manager = CLLocationManager()
    private var callback: ((Double, Double, String?) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 获取当前位置，回调参数为 GCJ-02 坐标；error 非空表示失败
    func fetch(_ completion: @escaping (Double, Double, String?) -> Void) {
        callback = completion
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization() // 授权后由代理回调继续
        case .denied, .restricted:
            finish(0, 0, "定位权限被拒绝：请到 设置 → 隐私与安全性 → 定位服务 允许本App")
        default:
            manager.requestLocation()
        }
    }

    private func finish(_ lat: Double, _ lng: Double, _ error: String?) {
        let cb = callback
        callback = nil
        cb?(lat, lng, error)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            finish(0, 0, "定位权限被拒绝：请到 设置 → 隐私与安全性 → 定位服务 允许本App")
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let gcj = Self.wgs84ToGcj02(lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
        finish(gcj.lat, gcj.lng, nil)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(0, 0, "定位失败：\(error.localizedDescription)")
    }

    /// 标准国测局 WGS-84 → GCJ-02 火星坐标转换算法
    static func wgs84ToGcj02(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        // 粗略判断是否在中国境外（境外无偏移）
        if lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271 {
            return (lat, lng)
        }
        let a = 6378245.0
        let ee = 0.00669342162296594323

        func transformLat(_ x: Double, _ y: Double) -> Double {
            var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
            ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
            ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
            ret += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
            return ret
        }
        func transformLng(_ x: Double, _ y: Double) -> Double {
            var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
            ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
            ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
            ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
            return ret
        }

        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        var dLat = transformLat(lng - 105.0, lat - 35.0)
        var dLng = transformLng(lng - 105.0, lat - 35.0)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return (lat + dLat, lng + dLng)
    }
}

struct BrowserView: UIViewRepresentable {
    @ObservedObject var core: WebCore

    func makeUIView(context: Context) -> WKWebView { core.webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

extension UIApplication {
    static func topViewController(_ base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first) -> UIViewController? {
        if let nav = base as? UINavigationController { return topViewController(nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(presented) }
        return base
    }
}
