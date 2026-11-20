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

// MARK: - 主题（统一淡色系，全 App 图标均使用 SF Symbols 矢量符号）

enum Theme {
    /// 统一淡蓝主题色
    static let accent = Color(red: 0.45, green: 0.62, blue: 0.94)
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

// MARK: - 常设位置（可增删，保存在本地）

struct SavedPlace: Codable, Identifiable {
    let name: String
    let lat: Double
    let lng: Double
    var id: String { "\(name)|\(lat)|\(lng)" }
}

extension LocationSettings {
    static let presetsKey = "savedPresets"

    static let defaultPresets: [SavedPlace] = [
        SavedPlace(name: "苏州（沙钢本地）", lat: 31.2989, lng: 120.5853),
        SavedPlace(name: "上海人民广场", lat: 31.2335, lng: 121.4692),
        SavedPlace(name: "上海张江", lat: 31.2040, lng: 121.5880),
        SavedPlace(name: "南京新街口", lat: 32.0415, lng: 118.7785)
    ]

    static func loadPresets() -> [SavedPlace] {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let arr = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            return arr
        }
        return defaultPresets
    }

    static func savePresets(_ p: [SavedPlace]) {
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: presetsKey)
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

    // 地名搜索状态
    @State private var searchText = ""
    @State private var searchResults: [PlaceResult] = []
    @State private var searching = false
    @State private var searchHint = ""
    @State private var pickedPlace = ""

    // 常设位置（可增删）
    @State private var presets: [SavedPlace] = LocationSettings.loadPresets()
    @State private var saveToPresetsAfterFetch = false

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
                            .tint(Theme.accent)
                        if !pickedPlace.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.red)
                                Text(pickedPlace)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
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
                        Text("坐标已自动转换为 GCJ-02 火星坐标系，页面地图不会偏移。")
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
                    Section(header: Text("常设位置"), footer: Text("左滑可删除；点「添加当前位置」把手机定位存入列表。")) {
                        ForEach(presets) { p in
                            Button {
                                latText = String(format: "%.6f", p.lat)
                                lngText = String(format: "%.6f", p.lng)
                                enabled = true
                                pickedPlace = p.name
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Theme.accent)
                                    Text(p.name)
                                    Spacer()
                                    Text(String(format: "%.4f, %.4f", p.lat, p.lng))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            presets.remove(atOffsets: offsets)
                            LocationSettings.savePresets(presets)
                        }
                        Button {
                            saveCurrentAsPreset()
                        } label: {
                            Label("添加当前位置", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Theme.accent)
                        }
                    }

                    // 手动搜索位置：输入地名，自动查出坐标并转为火星坐标
                    Section(header: Text("搜索位置"), footer: Text("输入地名搜索，点选结果即自动填入坐标。可搜城市、街道、小区、地标；搜不到时试试更具体的关键词，如「张家港市锦丰镇」。")) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("输入地名关键词", text: $searchText)
                                .submitLabel(.search)
                                .onSubmit { runPlaceSearch() }
                            if searching {
                                ProgressView()
                            } else {
                                Button {
                                    runPlaceSearch()
                                } label: {
                                    Text("搜索")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        if !searchHint.isEmpty {
                            Text(searchHint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ForEach(searchResults) { r in
                            Button {
                                pickPlace(r)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.name)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                        Text(String(format: "%.4f, %.4f", r.lat, r.lng))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
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

    /// 把当前位置存入常设列表
    private func saveCurrentAsPreset() {
        if let dl = deviceLat, let dg = deviceLng {
            doSavePreset(dl, dg)
        } else if let c = LocationSettings.cachedDevice() {
            doSavePreset(c.lat, c.lng)
        } else {
            saveToPresetsAfterFetch = true
            fetchDevice()
        }
    }

    private func doSavePreset(_ lat: Double, _ lng: Double) {
        let place = SavedPlace(name: "我的位置 \(presets.count + 1)", lat: lat, lng: lng)
        presets.append(place)
        LocationSettings.savePresets(presets)
        searchHint = "已添加到常设位置"
    }

    /// 执行地名搜索
    private func runPlaceSearch() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        searching = true
        searchHint = ""
        searchResults = []
        PlaceSearch.search(q) { results, err in
            DispatchQueue.main.async {
                searching = false
                if let err = err {
                    searchHint = err
                    return
                }
                searchResults = results
                if results.isEmpty {
                    searchHint = "没搜到这个地址，试试更具体的关键词，如「张家港市锦丰镇」"
                }
            }
        }
    }

    /// 点选搜索结果：填入坐标（已是 GCJ-02）
    private func pickPlace(_ r: PlaceResult) {
        latText = String(format: "%.6f", r.lat)
        lngText = String(format: "%.6f", r.lng)
        enabled = true
        pickedPlace = r.name
        searchResults = []
        searchHint = "已选用：\(r.name)"
    }

    private func fetchDevice() {
        fetching = true
        deviceStatus = ""
        DeviceLocator.shared.fetch { lat, lng, err in
            DispatchQueue.main.async {
                fetching = false
                if let err = err {
                    deviceStatus = err
                    saveToPresetsAfterFetch = false
                    return
                }
                deviceLat = lat
                deviceLng = lng
                deviceCoord = String(format: "%.6f, %.6f", lng, lat)
                deviceStatus = "获取成功（GCJ-02）"
                if saveToPresetsAfterFetch {
                    saveToPresetsAfterFetch = false
                    doSavePreset(lat, lng)
                }
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

// MARK: - 地名搜索（ArcGIS 世界地理编码 + OpenStreetMap Nominatim + Photon，三源并发免密钥）

struct PlaceResult: Identifiable {
    let id = UUID()
    let name: String
    let lat: Double // 已转 GCJ-02
    let lng: Double
    var coordText: String { String(format: "%.4f, %.4f", lat, lng) }
}

enum PlaceSearch {
    /// 三源并发搜索，结果合并去重（GCJ-02 坐标）
    static func search(_ query: String, completion: @escaping ([PlaceResult], String?) -> Void) {
        let qs = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var merged: [PlaceResult] = []
        let lock = NSLock()
        let group = DispatchGroup()

        let sources: [(String, (String, @escaping ([PlaceResult]) -> Void) -> Void)] = [
            ("arcgis", fetchArcGIS),
            ("nominatim", fetchNominatim),
            ("photon", fetchPhoton)
        ]
        for s in sources {
            group.enter()
            s.1(qs) { r in
                lock.lock()
                merged += r
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            // 按 名称+坐标 去重，最多 10 条
            var seen = Set<String>()
            var out: [PlaceResult] = []
            for r in merged {
                let key = String(r.name.prefix(16)) + String(format: "|%.3f,%.3f", r.lat, r.lng)
                if seen.insert(key).inserted { out.append(r) }
                if out.count >= 10 { break }
            }
            completion(out, nil)
        }
    }

    // ---------- ArcGIS World Geocoder（对中文地址/POI 支持最好，主源） ----------
    private static func fetchArcGIS(_ qs: String, _ completion: @escaping ([PlaceResult]) -> Void) {
        let urlStr = "https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates" +
            "?f=json&maxLocations=8&outFields=Match_addr,City,Region,Subregion&singleLine=\(qs)"
        request(urlStr) { obj in
            var out: [PlaceResult] = []
            if let dict = obj as? [String: Any],
               let candidates = dict["candidates"] as? [[String: Any]] {
                for c in candidates {
                    guard let addr = c["address"] as? String,
                          let loc = c["location"] as? [String: Any],
                          let lng = loc["x"] as? Double,
                          let lat = loc["y"] as? Double else { continue }
                    append(&out, name: addr, wgsLat: lat, wgsLng: lng)
                }
            }
            completion(out)
        }
    }

    // ---------- OpenStreetMap Nominatim ----------
    private static func fetchNominatim(_ qs: String, _ completion: @escaping ([PlaceResult]) -> Void) {
        request("https://nominatim.openstreetmap.org/search?q=\(qs)&format=json&limit=8&accept-language=zh-CN") { obj in
            var out: [PlaceResult] = []
            if let arr = obj as? [[String: Any]] {
                for item in arr {
                    guard let latStr = item["lat"] as? String, let lat = Double(latStr),
                          let lonStr = item["lon"] as? String, let lng = Double(lonStr),
                          let name = item["display_name"] as? String else { continue }
                    append(&out, name: name, wgsLat: lat, wgsLng: lng)
                }
            }
            completion(out)
        }
    }

    // ---------- Photon (Komoot) ----------
    private static func fetchPhoton(_ qs: String, _ completion: @escaping ([PlaceResult]) -> Void) {
        request("https://photon.komoot.io/api/?q=\(qs)&limit=8") { obj in
            var out: [PlaceResult] = []
            if let dict = obj as? [String: Any],
               let features = dict["features"] as? [[String: Any]] {
                for f in features {
                    guard let geo = f["geometry"] as? [String: Any],
                          let coords = geo["coordinates"] as? [Any], coords.count >= 2,
                          let lng = coords[0] as? Double, let lat = coords[1] as? Double else { continue }
                    let p = f["properties"] as? [String: Any] ?? [:]
                    let parts = [p["name"], p["street"], p["district"], p["city"], p["county"], p["state"], p["country"]]
                        .compactMap { $0 as? String }
                        .filter { !$0.isEmpty }
                    var deduped: [String] = []
                    for part in parts where deduped.last != part { deduped.append(part) }
                    append(&out, name: deduped.isEmpty ? "未知地点" : deduped.joined(separator: " "), wgsLat: lat, wgsLng: lng)
                }
            }
            completion(out)
        }
    }

    private static func request(_ urlStr: String, _ completion: @escaping (Any?) -> Void) {
        guard let url = URL(string: urlStr) else { completion(nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("AlbumUnlockApp/2.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let obj = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) })
            DispatchQueue.global(qos: .userInitiated).async {
                completion(obj)
            }
        }.resume()
    }

    private static func append(_ out: inout [PlaceResult], name: String, wgsLat: Double, wgsLng: Double) {
        let gcj = DeviceLocator.wgs84ToGcj02(lat: wgsLat, lng: wgsLng)
        out.append(PlaceResult(name: name, lat: gcj.lat, lng: gcj.lng))
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var core = WebCore()
    @State private var urlField = "http://qypt.shasteel.cn/mobile-apps/open"
    @State private var showLocationSheet = false
    @State private var showToolSheet = false
    @State private var locationSettings: LocationSettings = .load()
    @State private var toastText: String?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部融合式玻璃地址栏（iOS 液态玻璃风格）
            HStack(spacing: 0) {
                navIcon("chevron.left", active: core.canGoBack) { core.webView.goBack() }
                navIcon("chevron.right", active: core.canGoForward) { core.webView.goForward() }

                Rectangle()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 6)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(.secondaryLabel))
                    TextField("搜索或输入网址", text: $urlField)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: 14))
                        .submitLabel(.go)
                        .onSubmit { goToURL() }
                }

                Button {
                    core.webView.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(.secondaryLabel))
                        .frame(width: 30, height: 30)
                }

                Button {
                    goToURL()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(width: 34, height: 34)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 4)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.05)))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top))

            BrowserView(core: core)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 关键：关闭 SwiftUI 的键盘自动避让，由 WebKit 内部滚动输入框到键盘上方。
                // 否则双重避让会让第三方键盘（讯飞/搜狗）的工具条与键盘脱节、页面出现空隙。
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .bottom) {
            // 底部提示气泡（替代原状态行）
            if let t = toastText {
                ToastBubble(text: t)
                    .padding(.bottom, 118)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // 悬浮工具按钮（玻璃质感，淡蓝色图标）
            Button {
                showToolSheet = true
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 21))
                    .foregroundColor(Theme.accent)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 44)
        }
        .onChange(of: core.statusLine) { newValue in
            guard !newValue.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.25)) { toastText = newValue }
        }
        .task(id: toastText) {
            guard toastText != nil else { return }
            let cur = toastText
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if toastText == cur {
                withAnimation(.easeOut(duration: 0.3)) { toastText = nil }
            }
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

    /// 地址栏内嵌导航图标按钮（融合式，无独立背景）
    private func navIcon(_ systemName: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(active ? Color(.label) : Color(.tertiaryLabel))
                .frame(width: 34, height: 34)
        }
        .disabled(!active)
    }
}

// MARK: - 底部提示气泡

struct ToastBubble: View {
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.accent)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(.label))
                .multilineTextAlignment(.center)  // 多行时每一行都居中
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 320)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
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
                Section(header: Text("相册解锁"), footer: Text("关闭后页面将保留原始的拍照限制，刷新页面生效。")) {
                    Toggle(isOn: Binding(
                        get: { core.unlockEnabled },
                        set: { core.setUnlockEnabled($0) }
                    )) {
                        Label("自动解锁相册", systemImage: "lock.open.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .tint(Theme.accent)
                    if core.unlockEnabled {
                        toolRow("doc.text.magnifyingglass", title: "扫描文件框", subtitle: "查看上传框解锁状态") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { core.scanFileInputs() }
                        }
                    }
                }
                Section(header: Text("定位")) {
                    toolRow("location.fill", title: "定位设置", subtitle: "手机定位 / 手动坐标 / 地名搜索") {
                        onOpenLocation()
                    }
                }
                Section(header: Text("排查")) {
                    toolRow("antenna.radiowaves.left.and.right", title: "调试", subtitle: "导出凭据与子应用地址") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { core.dumpDebugInfo() }
                    }
                    toolRow("arrow.clockwise", title: "重新加载页面", subtitle: nil) {
                        dismiss()
                        core.webView.reload()
                    }
                }
                Section(header: Text("维护"), footer: Text("清除缓存会同时清除登录状态，需要重新登录门户。")) {
                    toolRow("trash.fill", title: "清除所有缓存", subtitle: "将退出登录", destructive: true) {
                        dismiss()
                        core.clearAllCache()
                    }
                }
                Section(header: Text("当前状态")) {
                    let s = core.quickStats
                    Text(s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工具箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    /// 统一风格工具行：SF Symbols 矢量图标 + 淡蓝主题底色
    private func toolRow(_ icon: String, title: String, subtitle: String?,
                         destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(destructive ? .red : Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(destructive ? Color.red.opacity(0.12) : Theme.accent.opacity(0.13))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(destructive ? .red : .primary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - WebView 核心

final class WebCore: NSObject, ObservableObject, WKNavigationDelegate {
    static let unlockKey = "albumUnlockEnabled"

    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var statusLine = ""
    @Published var quickStats = "尚未加载页面"
    @Published var unlockEnabled = true

    private var observers: [NSKeyValueObservation] = []
    private var locationSettings: LocationSettings = .load()

    /// 预置脚本：解锁开关 + 定位模拟参数
    private var combinedPrelude: String {
        "window.__albumUnlockEnabled = \(unlockEnabled); " + locationSettings.preludeScript
    }

    override init() {
        let cfg = WKWebViewConfiguration()
        let controller = cfg.userContentController
        let settings = LocationSettings.load()
        let preludeSource = "window.__albumUnlockEnabled = \(UserDefaults.standard.object(forKey: Self.unlockKey) as? Bool ?? true); " + settings.preludeScript
        // 预置脚本：先写入解锁开关与定位模拟参数（所有 frame、文档开始时）
        let prelude = WKUserScript(
            source: preludeSource,
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
        unlockEnabled = UserDefaults.standard.object(forKey: Self.unlockKey) as? Bool ?? true
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self

        observers.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in
            self?.canGoBack = w.canGoBack
        })
        observers.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in
            self?.canGoForward = w.canGoForward
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
            source: combinedPrelude,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        controller.addUserScript(WKUserScript(
            source: AlbumUnlockScript.source,
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }

    /// 切换相册解锁总开关：保存、重建脚本并刷新页面立即生效
    func setUnlockEnabled(_ on: Bool) {
        unlockEnabled = on
        UserDefaults.standard.set(on, forKey: Self.unlockKey)
        rebuildScripts()
        webView.reload()
        showToast(on ? "🔓 相册解锁已开启" : "🔒 相册解锁已关闭")
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
          if (!window.__albumUnlockInstalled) { return '脚本未就绪，请刷新页面'; }
          var n = 0;
          document.querySelectorAll('input[type=file][capture]').forEach(function(i){
            i.removeAttribute('capture'); n++;
          });
          var s = window.__albumUnlockStats ? window.__albumUnlockStats() : {};
          return '已解锁 ' + (n + (s.unlocked || 0)) + ' 个上传框｜定位 ' + (s.fakeLocation || '未开启');
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

    /// 应用内轻提示：改为底部气泡（不再弹窗打断）
    func showToast(_ text: String) {
        quickStats = text
        statusLine = (statusLine == text) ? text + " " : text
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
