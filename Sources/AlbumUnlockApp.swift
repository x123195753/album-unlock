import SwiftUI
import WebKit

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
    var enabled: Bool
    var lat: Double
    var lng: Double

    static let defaultsKey = "fakeLocationSettings"

    static func load() -> LocationSettings {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode(LocationSettings.self, from: data) {
            return s
        }
        // 默认：开启，坐标给出一个示例值（GCJ-02，苏州）
        return LocationSettings(enabled: false, lat: 31.2989, lng: 120.5853)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    var preludeScript: String {
        "window.__albumFakeLocation = {enabled: \(enabled), lat: \(lat), lng: \(lng)};"
    }
}

struct LocationSettingsView: View {
    @Binding var settings: LocationSettings
    var onApply: (LocationSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var enabled: Bool
    @State private var latText: String
    @State private var lngText: String
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
        _enabled = State(initialValue: settings.wrappedValue.enabled)
        _latText = State(initialValue: String(format: "%.6f", settings.wrappedValue.lat))
        _lngText = State(initialValue: String(format: "%.6f", settings.wrappedValue.lng))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("模拟定位（wx.getLocation / 浏览器定位都会返回该坐标）")) {
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
                    if !errorText.isEmpty {
                        Text(errorText).font(.caption).foregroundColor(.red)
                    }
                }

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

                Section {
                    Button("保存并应用到当前页面") { apply() }
                    Button("关闭模拟（恢复真实定位）") {
                        enabled = false
                        apply()
                    }
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

    private func apply() {
        guard let lat = Double(latText), let lng = Double(lngText),
              lat >= -90, lat <= 90, lng >= -180, lng <= 180 else {
            errorText = "经纬度格式不正确（纬度 -90~90，经度 -180~180）"
            return
        }
        errorText = ""
        let s = LocationSettings(enabled: enabled, lat: lat, lng: lng)
        s.save()
        settings = s
        onApply(s)
        dismiss()
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var core = WebCore()
    @State private var urlField = "http://qypt.shasteel.cn/mobile-apps/open"
    @State private var shouldLoad = false
    @State private var showLocationSheet = false
    @State private var locationSettings: LocationSettings = .load()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(core.canGoBack ? "‹" : " ") { core.webView.goBack() }
                    .disabled(!core.canGoBack)
                    .font(.title2)
                Button(core.canGoForward ? "›" : " ") { core.webView.goForward() }
                    .disabled(!core.canGoForward)
                    .font(.title2)
                TextField("输入网址", text: $urlField, onCommit: { shouldLoad = true })
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .font(.footnote)
                Button("前往") { shouldLoad = true }
                    .font(.subheadline)
                Button("重载") { core.webView.reload() }
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                Button("🔓 解锁相册") { core.runUnlock() }
                Button("扫描文件框") { core.scanFileInputs() }
                Button(locationSettings.enabled ? "📍 模拟定位:开" : "📍 模拟定位:关") {
                    showLocationSheet = true
                }
                Spacer()
                Text(core.statusLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            BrowserView(core: core, urlToLoad: $urlField, shouldLoad: $shouldLoad)
        }
        .onAppear { shouldLoad = true }
        .sheet(isPresented: $showLocationSheet) {
            LocationSettingsView(settings: $locationSettings) { newSettings in
                core.applyLocationSettings(newSettings)
            }
        }
    }
}

// MARK: - WebView 核心

final class WebCore: NSObject, ObservableObject {
    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var statusLine = ""

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
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: s.preludeScript,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        controller.addUserScript(WKUserScript(
            source: AlbumUnlockScript.source,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))

        // 当前页立即生效：写入主 frame；若补丁已装好则整页刷新，让 iframe 子应用也拿到新坐标
        let js = """
        (function(){
          window.__albumFakeLocation = {enabled: \(s.enabled), lat: \(s.lat), lng: \(s.lng)};
          if (window.__albumUnlockInstalled) { location.reload(); }
          return 'applied';
        })()
        """
        webView.evaluateJavaScript(js) { _, _ in }
        statusLine = s.enabled ? "📍 \(String(format: "%.4f", s.lat)),\(String(format: "%.4f", s.lng))" : "定位模拟已关闭"
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
                self?.statusLine = (result as? String) ?? "脚本未就绪"
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

struct BrowserView: UIViewRepresentable {
    @ObservedObject var core: WebCore
    @Binding var urlToLoad: String
    @Binding var shouldLoad: Bool

    func makeUIView(context: Context) -> WKWebView { core.webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if shouldLoad {
            shouldLoad = false
            core.load(urlToLoad)
        }
    }
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
