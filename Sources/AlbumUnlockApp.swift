import SwiftUI
import WebKit
import CoreLocation
import MapKit
import UIKit

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
    /// 统一主色（恢复正常饱和度）
    static let accent = Color(red: 0.25, green: 0.50, blue: 0.95)
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

    /// 随机位置浮动：在给定坐标上叠加随机偏移（距离 5~50 米、方向随机，每次调用重新随机）
    static func jittered(lat: Double, lng: Double, on: Bool) -> (lat: Double, lng: Double) {
        guard on else { return (lat, lng) }
        let dist = Double.random(in: 5...50)              // 米
        let bearing = Double.random(in: 0..<(2 * .pi))    // 方向角
        let dLat = dist * cos(bearing) / 111_320.0
        let dLng = dist * sin(bearing) / (111_320.0 * max(0.1, cos(lat * .pi / 180.0)))
        return (lat + dLat, lng + dLng)
    }

    /// 计算当前要预置进页面的模拟坐标（含随机浮动）
    func fakeLocation(jitter: Bool) -> (enabled: Bool, lat: Double, lng: Double) {
        switch effectiveMode {
        case "off":
            return (false, lat, lng)
        case "device":
            if let c = Self.cachedDevice() {
                let p = Self.jittered(lat: c.lat, lng: c.lng, on: jitter)
                return (true, p.lat, p.lng)
            }
            return (false, lat, lng)
        default:
            let p = Self.jittered(lat: lat, lng: lng, on: jitter)
            return (enabled, p.lat, p.lng)
        }
    }

    /// jitter=true 时每次生成都带一个新的随机偏移（每次重建脚本/加载页面都会重新浮动）
    func preludeScript(jitter: Bool) -> String {
        let f = fakeLocation(jitter: jitter)
        return "window.__albumFakeLocation = {enabled: \(f.enabled), lat: \(f.lat), lng: \(f.lng)};"
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

// MARK: - 常设位置命名（新建 / 重命名共用）

struct PresetEdit: Identifiable {
    enum Mode: Equatable { case create, rename }
    let id = UUID()
    let mode: Mode
    let lat: Double
    let lng: Double
    var draft: String
}

/// 输入名称备注的小面板
struct PresetNameEditor: View {
    let title: String
    var onSave: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.onSave = onSave
        _text = State(initialValue: initialName)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("名称备注"),
                        footer: Text("只在本机列表里显示，方便区分各个位置。")) {
                    TextField("例如：常州新岚厂 / 家里", text: $text)
                        .submitLabel(.done)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
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

    // 常设位置（可增删、可改名称备注）
    @State private var presets: [SavedPlace] = LocationSettings.loadPresets()
    @State private var saveToPresetsAfterFetch = false
    @State private var presetEdit: PresetEdit?

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
                    Section(header: Text("常设位置"), footer: Text("左滑删除；点右侧铅笔可改名称备注。")) {
                        ForEach(presets) { p in
                            HStack(spacing: 10) {
                                Button {
                                    applyPreset(p)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(Theme.accent)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(p.name)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text(String(format: "%.4f, %.4f", p.lat, p.lng))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    presetEdit = PresetEdit(mode: .rename, lat: p.lat, lng: p.lng, draft: p.name)
                                } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(Theme.accent)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("重命名")
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
                        // 把上面填入的坐标（例如搜到的公司）存成常设位置并命名
                        Button {
                            let lat = Double(latText.trimmingCharacters(in: .whitespaces)) ?? settings.lat
                            let lng = Double(lngText.trimmingCharacters(in: .whitespaces)) ?? settings.lng
                            beginCreatePreset(lat, lng)
                        } label: {
                            Label("保存当前坐标", systemImage: "bookmark.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Theme.accent)
                        }
                    }

                    // 手动搜索位置：输入地名，自动查出坐标并转为火星坐标
                    Section(header: Text("搜索位置"), footer: Text("可搜企业名、地址或经纬度，点选即填入坐标。例：「常州新岚循环利用有限公司」「安宁路84号」「31.9164,119.9080」。搜企业名会自动忽略「有限公司」等后缀。")) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("企业名 / 地址 / 经纬度", text: $searchText)
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
                                        if let d = r.detail, !d.isEmpty, d != r.name {
                                            Text(d)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
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
            .sheet(item: $presetEdit) { edit in
                PresetNameEditor(title: edit.mode == .create ? "保存为常设位置" : "重命名",
                                 initialName: edit.draft) { name in
                    commitPresetEdit(edit, name: name)
                }
            }
        }
    }

    /// 选用某个常设位置
    private func applyPreset(_ p: SavedPlace) {
        latText = String(format: "%.6f", p.lat)
        lngText = String(format: "%.6f", p.lng)
        enabled = true
        pickedPlace = p.name
    }

    /// 打开命名面板（新建）
    private func beginCreatePreset(_ lat: Double, _ lng: Double) {
        presetEdit = PresetEdit(mode: .create, lat: lat, lng: lng,
                                draft: "我的位置 \(presets.count + 1)")
    }

    /// 提交新建 / 重命名
    private func commitPresetEdit(_ edit: PresetEdit, name: String) {
        switch edit.mode {
        case .create:
            presets.append(SavedPlace(name: name, lat: edit.lat, lng: edit.lng))
            searchHint = "已添加到常设位置"
        case .rename:
            if let i = presets.firstIndex(where: {
                abs($0.lat - edit.lat) < 1e-9 && abs($0.lng - edit.lng) < 1e-9
            }) {
                presets[i] = SavedPlace(name: name, lat: presets[i].lat, lng: presets[i].lng)
            }
        }
        LocationSettings.savePresets(presets)
    }

    /// 把当前位置存入常设列表（先让用户命名）
    private func saveCurrentAsPreset() {
        if let dl = deviceLat, let dg = deviceLng {
            beginCreatePreset(dl, dg)
        } else if let c = LocationSettings.cachedDevice() {
            beginCreatePreset(c.lat, c.lng)
        } else {
            saveToPresetsAfterFetch = true
            fetchDevice()
        }
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
                    searchHint = "没搜到。试试只输关键字（如「常州 新岚」），或直接输经纬度。"
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
                    beginCreatePreset(lat, lng)
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
    /// 地址等补充信息（Apple 地图会给出完整地址）
    var detail: String? = nil
    let lat: Double // 已转 GCJ-02
    let lng: Double
    var coordText: String { String(format: "%.4f, %.4f", lat, lng) }
}

enum PlaceSearch {
    /// 企业名 / 地址 / 坐标统一搜索：
    /// 1) Apple 地图（中国大陆由高德供数，含企业商户 POI，无需 Key）
    /// 2) ArcGIS / Nominatim / Photon 兜底地址与地标
    /// 3) 全名搜不到时逐级简化关键词（去公司后缀 → 去行业词），兼容工商名与口语名不一致
    static func search(_ query: String, completion: @escaping ([PlaceResult], String?) -> Void) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { completion([], "请输入关键词"); return }
        if let coord = parseCoordinate(q) { completion([coord], nil); return }

        // 整体 9 秒上限：多级重试时不会一直转圈
        let lock = NSLock()
        var done = false
        let finish: ([PlaceResult], String?) -> Void = { results, err in
            lock.lock(); let first = !done; done = true; lock.unlock()
            guard first else { return }
            completion(results, err)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 9) {
            lock.lock(); let first = !done; done = true; lock.unlock()
            guard first else { return }
            DispatchQueue.main.async { completion([], "搜索超时，换个关键词或检查网络") }
        }
        runLevel(queryVariants(q), index: 0, rawQuery: q, completion: finish)
    }

    // MARK: 分级检索（上一级没有结果才降级重试）

    private static func runLevel(_ levels: [String], index: Int, rawQuery: String,
                                 completion: @escaping ([PlaceResult], String?) -> Void) {
        guard index < levels.count else { completion([], nil); return }
        var merged: [PlaceResult] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let sources: [(String, (String, @escaping ([PlaceResult]) -> Void) -> Void)] = [
            ("apple", fetchAppleMaps),
            ("arcgis", fetchArcGIS),
            ("nominatim", fetchNominatim),
            ("photon", fetchPhoton)
        ]
        for s in sources {
            group.enter()
            s.1(levels[index]) { r in
                lock.lock(); merged += r; lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            var seen = Set<String>()
            var out: [PlaceResult] = []
            for r in merged {
                let key = String(r.name.prefix(20)) + String(format: "|%.3f,%.3f", r.lat, r.lng)
                if seen.insert(key).inserted { out.append(r) }
            }
            if out.isEmpty, index + 1 < levels.count {
                // 全名（或含地区全名）无结果，换更短的关键词再来一轮
                runLevel(levels, index: index + 1, rawQuery: rawQuery, completion: completion)
                return
            }
            out.sort { rank($0, rawQuery) > rank($1, rawQuery) }
            completion(Array(out.prefix(12)), nil)
        }
    }

    // MARK: 关键词变体

    /// 全名 → 去掉公司后缀 → 再去掉行业词，只留「地名 + 专名」
    private static func queryVariants(_ q: String) -> [String] {
        var out = [q]
        var s = q
        for suf in ["股份有限公司", "有限责任公司", "有限公司", "分公司", "公司", "集团", "厂"]
        where s.hasSuffix(suf) && s.count > suf.count {
            s = String(s.dropLast(suf.count))
            break
        }
        if s != q, !s.isEmpty { out.append(s) }

        let industry = ["资源循环利用", "循环利用", "再生资源", "新材料", "科技", "环保", "实业",
                        "贸易", "物流", "机械", "建设", "工程", "制造", "服务", "发展",
                        "技术", "商贸", "工贸", "制品", "材料"]
        var core = s
        for w in industry { core = core.replacingOccurrences(of: w, with: "") }
        core = core.trimmingCharacters(in: .whitespaces)
        if core != s, core.count >= 2, !out.contains(core) { out.append(core) }
        return out
    }

    /// 直接输入经纬度："31.2989,120.5853"（纬,经）或 "120.5853,31.2989" 均可
    private static func parseCoordinate(_ s: String) -> PlaceResult? {
        let parts = s.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        var lat = parts[0], lng = parts[1]
        if abs(lat) > 90, abs(lng) <= 90 { swap(&lat, &lng) }
        guard abs(lat) <= 90, abs(lng) <= 180, lat != 0, lng != 0 else { return nil }
        return PlaceResult(name: String(format: "坐标 %.5f, %.5f", lat, lng),
                           detail: "手动输入的经纬度（GCJ-02）", lat: lat, lng: lng)
    }

    /// 相关度：查询里的有效字有多少出现在结果名称/地址中
    private static func rank(_ r: PlaceResult, _ query: String) -> Double {
        let ignore = Set("的省市县区镇街道路号有限公司股份集团厂")
        let qs = query.filter { !ignore.contains($0) && !$0.isWhitespace }
        guard !qs.isEmpty else { return 0 }
        let hay = r.name + " " + (r.detail ?? "")
        var hit = 0
        for ch in qs where hay.contains(ch) { hit += 1 }
        var s = Double(hit) / Double(qs.count)
        if r.name.contains(query) { s += 0.5 }
        else if r.name.contains(String(qs.prefix(2))) { s += 0.15 }
        return s
    }

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    // ---------- Apple 地图（中国大陆由高德供数，企业/商户 POI 最全，无需 Key） ----------
    private static func fetchAppleMaps(_ query: String, _ completion: @escaping ([PlaceResult]) -> Void) {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        // 偏向华东（沙钢一带），避免同名地点飘到别的城市或国外
        req.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.8, longitude: 119.6),
                                        span: MKCoordinateSpan(latitudeDelta: 16, longitudeDelta: 20))
        MKLocalSearch(request: req).start { resp, _ in
            var out: [PlaceResult] = []
            for item in (resp?.mapItems ?? []).prefix(8) {
                let c = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(c) else { continue }
                // 中国大陆的 Apple 地图坐标本身已是 GCJ-02（与高德一致），不再二次偏移
                out.append(PlaceResult(name: item.name ?? "未知地点",
                                       detail: item.placemark.title,
                                       lat: c.latitude, lng: c.longitude))
            }
            completion(out)
        }
    }

    // ---------- ArcGIS World Geocoder（对中文地址支持好） ----------
    private static func fetchArcGIS(_ query: String, _ completion: @escaping ([PlaceResult]) -> Void) {
        let qs = enc(query)
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
    private static func fetchNominatim(_ query: String, _ completion: @escaping ([PlaceResult]) -> Void) {
        let qs = enc(query)
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
    private static func fetchPhoton(_ query: String, _ completion: @escaping ([PlaceResult]) -> Void) {
        let qs = enc(query)
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
    private let homeURL = "http://qypt.shasteel.cn/mobile-apps/open"
    @State private var showLocationSheet = false
    @State private var showToolSheet = false
    @State private var locationSettings: LocationSettings = .load()
    @State private var toast: ToastMessage?

    var body: some View {
        ZStack {
            // 状态栏 / Home 指示条区域露出的底色（调色盘可改）
            Color(albumHex: core.navColor).ignoresSafeArea()
            VStack(spacing: 0) {
                // 地址栏（工具箱可开关）：与状态栏色带连成一体
                if core.addressBarEnabled {
                    AddressBar(core: core)
                } else {
                    // 隐藏地址栏时顶部也留一段色带，网页不贴着状态栏
                    Color.clear.frame(height: 16)
                }
                BrowserView(core: core)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // 网页延伸到屏幕底部：底部安全区露出的是页面自身背景色，
                    // 不再显示调色盘的导航色
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        // 淡蓝底上需要深色状态栏图标；同时 App 弹层统一浅色
        .preferredColorScheme(.light)
        // 关键：关闭 SwiftUI 的键盘自动避让，由 WebKit 内部滚动输入框到键盘上方。
        // 否则双重避让会让第三方键盘（讯飞/搜狗）的工具条与键盘脱节、页面出现空隙。
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .bottom) {
            // 全 App 唯一的提示出口：底部毛玻璃气泡（网页内自绘提示已移除，不再双份）
            if let t = toast {
                ToastBubble(message: t)
                    .padding(.bottom, 108)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // 悬浮工具按钮（饱和渐变 + 白色图标）
            Button {
                showToolSheet = true
            } label: {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 21))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle().fill(
                            LinearGradient(colors: [Color(red: 0.30, green: 0.52, blue: 0.98),
                                                    Color(red: 0.18, green: 0.40, blue: 0.92)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    )
                    .shadow(color: Color(red: 0.25, green: 0.47, blue: 0.95).opacity(0.45), radius: 9, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 44)
        }
        .onChange(of: core.toast) { newValue in
            guard let t = newValue else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { toast = t }
        }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            let cur = toast?.id
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast?.id == cur {
                withAnimation(.easeOut(duration: 0.25)) { toast = nil }
            }
        }
        .onAppear {
            core.load(homeURL)
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
}

// MARK: - 底部提示气泡（全 App 统一样式）

/// 气泡语义：决定图标与图标颜色（统一为一种视觉语言）
enum ToastKind {
    case info, success, locate, warning

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .locate: return "location.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .info: return Theme.accent
        case .success: return .green
        case .locate: return .red
        case .warning: return .orange
        }
    }
}

/// 一条提示消息（id 用于让重复文字也能重新触发动画与计时）
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let kind: ToastKind

    init(_ text: String, kind: ToastKind = .info) {
        self.text = text
        self.kind = kind
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

/// 毛玻璃胶囊：图标 + 单行文案（宽度随内容自适应，过长自动缩字）
struct ToastBubble: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: message.kind.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(message.kind.color)
            Text(message.text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 19, style: .continuous).fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
    }
}

// MARK: - 悬浮工具菜单

// MARK: - 调色盘（状态栏 / 网页导航条统一色）

/// 预设色块：点选即时预览
struct PaletteOption: Identifiable {
    let hex: String
    let name: String
    var id: String { hex }
    static let presets: [PaletteOption] = [
        PaletteOption(hex: "#F0F4F8", name: "灰蓝"),
        PaletteOption(hex: "#D6E8FA", name: "淡蓝"),
        PaletteOption(hex: "#CFE3F7", name: "天蓝"),
        PaletteOption(hex: "#DDF2E7", name: "薄荷绿"),
        PaletteOption(hex: "#FAE4EA", name: "樱粉"),
        PaletteOption(hex: "#EAE3F8", name: "雾紫"),
        PaletteOption(hex: "#FCEBD8", name: "杏橙"),
        PaletteOption(hex: "#FAF3D9", name: "奶油黄"),
        PaletteOption(hex: "#FFFFFF", name: "纯白")
    ]
}

extension Color {
    /// "#RRGGBB" → Color（非法输入回退灰色）
    init(albumHex hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        if h.count == 6 {
            self.init(red: Double((v >> 16) & 0xFF) / 255,
                      green: Double((v >> 8) & 0xFF) / 255,
                      blue: Double(v & 0xFF) / 255)
        } else {
            self.init(.systemGray5)
        }
    }

    /// Color → "#RRGGBB"（供自定义取色器写回）
    var albumHex: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: nil)
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

// MARK: - 地址栏（工具箱可开关）

struct AddressBar: View {
    @ObservedObject var core: WebCore
    @State private var text = ""
    @FocusState private var focused: Bool

    /// 后退/前进：走联合会话历史，iframe 子应用内部的导航也能回退；不可用时置灰
    private func historyButton(_ icon: String, _ delta: Int, enabled: Bool) -> some View {
        Button {
            core.evaluateHistory(delta)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(enabled ? Theme.accent : Color(.tertiaryLabel))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    var body: some View {
        HStack(spacing: 8) {
            // 前部：后退 / 前进（联合会话历史，含 iframe 子应用内部导航）
            historyButton("chevron.left", -1, enabled: core.canGoBack)
            historyButton("chevron.right", 1, enabled: core.canGoForward)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            TextField("输入网址访问", text: $text)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($focused)
                .onSubmit(go)

            // 后部：刷新 / 跳转（与前进后退统一的纯图标风格）
            Button {
                focused = false
                core.webView.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            let hasText = !text.isEmpty
            Button {
                go()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(hasText ? Theme.accent : Color(.tertiaryLabel))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        // 上下空位：上 10 / 下 30
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 30)
        .onAppear { if !focused { text = core.currentURLString } }
        .onChange(of: core.currentURLString) { newValue in
            // 正在输入时不覆盖
            if !focused { text = newValue }
        }
    }

    private func go() {
        focused = false
        core.navigate(to: text)
    }
}

struct ToolMenuView: View {
    @ObservedObject var core: WebCore
    var onOpenLocation: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("相册解锁")) {
                    // 带彩色徽章的开关行（与其他工具行风格一致）
                    HStack(spacing: 12) {
                        badge("lock.open.fill", color: .orange)
                        Text("自动解锁相册")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { core.unlockEnabled },
                            set: { core.setUnlockEnabled($0) }
                        ))
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, 2)
                    if core.unlockEnabled {
                        toolRow("doc.text.magnifyingglass", color: .teal, title: "扫描文件框") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { core.scanFileInputs() }
                        }
                    }
                }
                Section(header: Text("定位")) {
                    toolRow("location.viewfinder", color: .red, title: "定位设置") {
                        onOpenLocation()
                    }
                    // 随机位置浮动开关：每次定位在 5~50 米内随机偏移
                    HStack(spacing: 12) {
                        badge("shuffle", color: .mint)
                        Text("随机位置浮动")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { core.jitterEnabled },
                            set: { core.setJitterEnabled($0) }
                        ))
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, 2)
                }
                Section(header: Text("页面")) {
                    // 上传照片处理开关（EXIF + 分辨率适配机型）
                    HStack(spacing: 12) {
                        badge("camera.fill", color: .cyan)
                        Text("上传加EXIF信息")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { core.exifEnabled },
                            set: { core.setExifEnabled($0) }
                        ))
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, 2)
                    // 地址栏开关
                    HStack(spacing: 12) {
                        badge("globe", color: .teal)
                        Text("显示地址栏")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { core.addressBarEnabled },
                            set: { core.setAddressBar($0) }
                        ))
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, 2)
                    // 网页美化开关（去边框 + 禁拖动）
                    HStack(spacing: 12) {
                        badge("paintbrush.fill", color: .purple)
                        Text("网页美化（去边框）")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { core.beautifyEnabled },
                            set: { core.setBeautifyEnabled($0) }
                        ))
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, 2)
                    toolRow("arrow.clockwise", color: .blue, title: "重新载入") {
                        dismiss()
                        core.webView.reload()
                    }
                }
                Section(header: Text("外观 · 状态栏颜色"), footer: Text("点色块立即预览：状态栏与网页导航条同步变色。右侧取色器可选任意颜色。")) {
                    // 调色盘：点色块即时预览
                    HStack(spacing: 12) {
                        badge("paintpalette.fill", color: .indigo)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(PaletteOption.presets) { p in
                                    Button {
                                        core.setNavColor(p.hex)
                                    } label: {
                                        Circle()
                                            .fill(Color(albumHex: p.hex))
                                            .frame(width: 30, height: 30)
                                            .overlay(
                                                Circle().stroke(
                                                    core.navColor == p.hex ? Color.primary : Color.primary.opacity(0.12),
                                                    lineWidth: core.navColor == p.hex ? 2.5 : 1
                                                )
                                            )
                                            .overlay(alignment: .center) {
                                                if core.navColor == p.hex {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(.primary.opacity(0.75))
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(p.name)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 2)
                        }
                        // 自定义取色器
                        ColorPicker("", selection: Binding(
                            get: { Color(albumHex: core.navColor) },
                            set: { core.setNavColor($0.albumHex) }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 32, height: 32)
                    }
                    .padding(.vertical, 2)
                }
                Section(header: Text("维护")) {
                    toolRow("trash.fill", color: .pink, title: "清除所有缓存", destructive: true) {
                        dismiss()
                        core.clearAllCache()
                    }
                }
                Section(header: Text("当前状态")) {
                    let s = core.quickStats
                    Text(s)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text("版本")
                        Spacer()
                        Text(appVersion)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("工具箱")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 版本号（每次构建递增，用于区分安装的包）
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    /// 彩色徽章（32×32 圆角 9，白色矢量图标）
    private func badge(_ icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [color, color.opacity(0.72)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
    }

    /// 彩色徽章工具行（仅标题）
    private func toolRow(_ icon: String, color: Color, title: String,
                         destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                badge(icon, color: color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(destructive ? .red : .primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - WebView 核心

final class WebCore: NSObject, ObservableObject, WKNavigationDelegate {
    static let unlockKey = "albumUnlockEnabled"
    static let beautifyKey = "albumBeautifyEnabled"
    static let navColorKey = "albumNavColor"
    static let addressBarKey = "albumAddressBarEnabled"
    static let exifKey = "albumExifEnabled"
    static let jitterKey = "albumJitterEnabled"
    /// 默认导航条/状态栏色：灰蓝（可在工具箱调色盘更换）
    static let defaultNavColor = "#F0F4F8"

    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    /// 联合会话历史长度（含 iframe 子应用的导航），用于估计后退是否可用
    private var jointHistoryLen = 1
    @Published var statusLine = ""
    /// 统一提示气泡的唯一数据源（网页内不再自绘提示）
    @Published var toast: ToastMessage?
    @Published var quickStats = "尚未加载页面"
    @Published var unlockEnabled = true
    /// 网页美化（去边框、禁拖动，不改动页面配色）
    @Published var beautifyEnabled = true
    /// 状态栏条 + 网页导航条统一色（十六进制，工具箱调色盘可改）
    @Published var navColor: String = UserDefaults.standard.string(forKey: "albumNavColor")
        ?? WebCore.defaultNavColor
    /// 地址栏显示开关（工具箱可切换）
    @Published var addressBarEnabled = UserDefaults.standard.object(forKey: "albumAddressBarEnabled") as? Bool ?? true
    /// 上传照片处理开关（EXIF + 分辨率适配机型）
    @Published var exifEnabled = UserDefaults.standard.object(forKey: "albumExifEnabled") as? Bool ?? true
    /// 随机位置浮动开关（每次应用定位时叠加 5~50 米随机偏移）
    @Published var jitterEnabled = UserDefaults.standard.object(forKey: "albumJitterEnabled") as? Bool ?? true
    /// 当前页面地址（供地址栏显示）
    @Published var currentURLString = ""

    @Published var pageTitle = ""
    @Published var barUIColor: UIColor?

    /// 标题栏背景：跟随网页主题色，无则用系统背景
    var barBackground: Color {
        guard let u = barUIColor else { return Color(.systemBackground) }
        return Color(uiColor: u)
    }

    /// 标题栏文字/图标颜色：背景亮用深字，背景深用白字
    var barForeground: Color {
        guard let u = barUIColor else { return Color(.label) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        return lum > 0.6 ? Color(.label) : .white
    }

    private var observers: [NSKeyValueObservation] = []
    private var locationSettings: LocationSettings = .load()
    /// 当前预置脚本里的模拟坐标（每次重建脚本时刷新）
    private var injectedFake: (enabled: Bool, lat: Double, lng: Double)?

    /// 预置脚本：解锁开关 + 网页美化开关 + 导航条颜色 + EXIF 开关 + 定位模拟参数
    private var combinedPrelude: String {
        "window.__albumUnlockEnabled = \(unlockEnabled); " +
        "window.__albumBeautify = \(beautifyEnabled); " +
        "window.__albumNavColor = '\(navColor)'; " +
        "window.__albumExifEnabled = \(exifEnabled); " +
        locationSettings.preludeScript(jitter: jitterEnabled)
    }

    override init() {
        let cfg = WKWebViewConfiguration()
        let controller = cfg.userContentController
        let settings = LocationSettings.load()
        let preludeSource = "window.__albumUnlockEnabled = \(UserDefaults.standard.object(forKey: Self.unlockKey) as? Bool ?? true); " +
            "window.__albumBeautify = \(UserDefaults.standard.object(forKey: Self.beautifyKey) as? Bool ?? true); " +
            "window.__albumNavColor = '\(UserDefaults.standard.string(forKey: Self.navColorKey) ?? Self.defaultNavColor)'; " +
            "window.__albumExifEnabled = \(UserDefaults.standard.object(forKey: Self.exifKey) as? Bool ?? true); " +
            settings.preludeScript(jitter: UserDefaults.standard.object(forKey: Self.jitterKey) as? Bool ?? true)
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
        injectedFake = locationSettings.fakeLocation(jitter: jitterEnabled)
        unlockEnabled = UserDefaults.standard.object(forKey: Self.unlockKey) as? Bool ?? true
        beautifyEnabled = UserDefaults.standard.object(forKey: Self.beautifyKey) as? Bool ?? true
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self

        // 禁止页面被拖动/回弹：关掉橡皮筋与横向拖拽，整页固定
        let sv = webView.scrollView
        sv.bounces = false
        sv.alwaysBounceVertical = false
        sv.alwaysBounceHorizontal = false
        sv.isDirectionalLockEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never

        observers.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] w, _ in
            self?.refreshNavAvailability()
        })
        observers.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] w, _ in
            self?.refreshNavAvailability()
        })
        // iframe 内部导航不会触发主框架 KVO，定期刷新可用状态
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshNavAvailability()
        }
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
            // 手机真实定位：拉取当前位置（成功后自动同步到页面并刷新）。
            // 抓取过程静默，成功/失败各只弹一条气泡，避免连续两条打断。
            refreshDeviceLocation(force: true, reloadAfter: true, announce: true)
            return
        }

        // 手动/关闭模式：当前页立即生效；整页刷新让 iframe 子应用同步。
        // rebuildScripts() 已把（含随机浮动的）最终坐标存进 injectedFake，这里直接用同一坐标
        if let f = injectedFake {
            let js = """
            (function(){
              window.__albumFakeLocation = {enabled: \(f.enabled), lat: \(f.lat), lng: \(f.lng)};
              if (window.__albumUnlockInstalled) { location.reload(); }
              return 'applied';
            })()
            """
            webView.evaluateJavaScript(js) { _, _ in }
            lastLocToastCoord = (f.lat, f.lng)
        }
        if s.effectiveMode == "manual" && s.enabled, let f = injectedFake {
            showToast(String(format: "定位已设为 %.4f, %.4f", f.lat, f.lng), kind: .locate)
        } else {
            showToast("定位模拟已关闭")
        }
    }

    /// 地址栏前进/后退：走联合会话历史（history.back/forward），
    /// 主框架没动过的门户场景下，iframe 子应用内部的历史也能回退/前进
    func evaluateHistory(_ delta: Int) {
        let js = delta < 0 ? "history.back()" : "history.forward()"
        webView.evaluateJavaScript(js) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshNavAvailability()
        }
    }

    /// 刷新前进/后退可用状态：主框架历史之外，联合会话历史（含 iframe）有更早条目时后退也可用
    func refreshNavAvailability() {
        webView.evaluateJavaScript("history.length") { [weak self] res, _ in
            guard let self = self, let n = res as? Int else { return }
            DispatchQueue.main.async {
                self.jointHistoryLen = n
                self.canGoBack = self.webView.canGoBack || n > 1
                self.canGoForward = self.webView.canGoForward
            }
        }
    }

    /// 重建预置脚本（定位设置变化后调用，保证后续导航带上新参数）
    private func rebuildScripts() {
        injectedFake = locationSettings.fakeLocation(jitter: jitterEnabled)
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
        showToast(on ? "相册解锁已开启" : "相册解锁已关闭", kind: on ? .success : .info)
    }

    /// 切换网页美化（去边框）：保存、重建注入脚本并刷新页面立即生效
    func setBeautifyEnabled(_ on: Bool) {
        beautifyEnabled = on
        UserDefaults.standard.set(on, forKey: Self.beautifyKey)
        rebuildScripts()
        webView.reload()
        showToast(on ? "网页美化已开启" : "网页美化已关闭", kind: on ? .success : .info)
    }

    /// 调色盘换色：状态栏条 + 网页导航条即时变色，无需刷新
    func setNavColor(_ hex: String) {
        navColor = hex
        UserDefaults.standard.set(hex, forKey: Self.navColorKey)
        rebuildScripts()
        webView.evaluateJavaScript("window.__albumSetNavColor && window.__albumSetNavColor('\(hex)')") { _, _ in }
    }

    /// 切换地址栏显示：保存偏好（无需刷新页面）
    func setAddressBar(_ on: Bool) {
        addressBarEnabled = on
        UserDefaults.standard.set(on, forKey: Self.addressBarKey)
    }

    /// 切换上传照片处理（EXIF + 分辨率适配）：保存、重建脚本并同步当前页标记
    func setExifEnabled(_ on: Bool) {
        exifEnabled = on
        UserDefaults.standard.set(on, forKey: Self.exifKey)
        rebuildScripts()
        webView.evaluateJavaScript("window.__albumExifEnabled = \(on)") { _, _ in }
        showToast(on ? "上传处理已开启" : "上传处理已关闭", kind: on ? .success : .info)
    }

    /// 切换随机位置浮动：保存偏好并刷新页面，让新偏移立即生效
    func setJitterEnabled(_ on: Bool) {
        jitterEnabled = on
        UserDefaults.standard.set(on, forKey: Self.jitterKey)
        rebuildScripts()
        webView.reload()
        showToast(on ? "位置随机浮动已开启" : "位置随机浮动已关闭", kind: on ? .success : .info)
    }

    /// 地址栏跳转：自动补协议头
    func navigate(to raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let _ = URL(string: s.contains("://") ? s : "http://" + s) else { return }
        if !s.contains("://") { s = "http://" + s }
        if let url = URL(string: s) {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: 首次就绪提示（合并解锁与定位状态，只弹一条）

    private var didAnnounceReady = false

    /// 是否真的在模拟定位（与 preludeScript 的判定保持一致）
    private var locationFaking: Bool {
        switch locationSettings.effectiveMode {
        case "off": return false
        case "device": return LocationSettings.cachedDevice() != nil
        default: return locationSettings.enabled
        }
    }

    private func announceReady() {
        if locationFaking {
            showToast("已就绪 · 定位已模拟", kind: .success)
        } else {
            showToast("已就绪 · 未模拟定位")
        }
    }

    // MARK: 手机真实定位

    private var lastDeviceFetchAt = Date.distantPast
    /// 上次弹过提示的注入坐标（定位真正变化才提示，避免重复打扰）
    private var lastLocToastCoord: (lat: Double, lng: Double)?

    /// 手机定位模式下：取当前位置（WGS-84 → GCJ-02），写入缓存并同步到当前页面。
    /// 每次页面导航时自动调用（30 秒节流），移动中也能拿到最新位置。
    func refreshDeviceLocation(force: Bool = false, reloadAfter: Bool = false, announce: Bool = false) {
        guard locationSettings.effectiveMode == "device" else { return }
        if !force, Date().timeIntervalSince(lastDeviceFetchAt) < 30 { return }
        lastDeviceFetchAt = Date()
        DeviceLocator.shared.fetch { [weak self] lat, lng, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.statusLine = "定位失败: \(error)"
                    // 仅在用户主动切换定位时提示，后台导航触发的失败不打扰
                    if announce { self.showToast("定位失败，请检查定位权限", kind: .warning) }
                }
                return
            }
            LocationSettings.cacheDevice(lat: lat, lng: lng)
            DispatchQueue.main.async {
                self.locationSettings.mode = "device"
                self.locationSettings.lat = lat
                self.locationSettings.lng = lng
                self.locationSettings.save()
                self.rebuildScripts()
                guard let f = self.injectedFake else { return }
                let js = "window.__albumFakeLocation = {enabled: \(f.enabled), lat: \(f.lat), lng: \(f.lng)};"
                self.webView.evaluateJavaScript(js) { _, _ in
                    if reloadAfter { self.webView.reload() }
                }
                let coord = String(format: "%.4f, %.4f", f.lat, f.lng)
                self.statusLine = "手机定位 " + coord
                self.quickStats = "手机定位 " + coord
                // 定位变化（含随机浮动产生的新坐标）即弹气泡提示
                let prev = self.lastLocToastCoord
                let moved = prev == nil
                    || abs(f.lat - prev!.lat) > 1e-5
                    || abs(f.lng - prev!.lng) > 1e-5
                self.lastLocToastCoord = (f.lat, f.lng)
                if announce || moved { self.showToast("定位已更新 " + coord, kind: .locate) }
            }
        }
    }

    // MARK: 网页主题色提取（标题栏自动变色）

    /// 取主 frame 的标题 + 主题色：meta theme-color > 页头元素背景 > body 背景
    static let themeJS = """
    (function(){
      var t = document.title || '';
      var c = null;
      try {
        var meta = document.querySelector('meta[name="theme-color"]');
        if (meta && meta.content) { c = meta.content; }
        if (!c) {
          var sel = ['header','.navbar','.nav-bar','#header','nav','.top-bar'];
          for (var i = 0; i < sel.length; i++) {
            var el = document.querySelector(sel[i]);
            if (el) {
              var bg = getComputedStyle(el).backgroundColor;
              if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') { c = bg; break; }
            }
          }
        }
        if (!c) {
          var bg2 = getComputedStyle(document.body).backgroundColor;
          if (bg2 && bg2 !== 'rgba(0, 0, 0, 0)' && bg2 !== 'transparent') c = bg2;
        }
      } catch(e) {}
      return JSON.stringify({t: t, c: c});
    })()
    """

    /// 解析 CSS 颜色字符串（#hex / rgb() / rgba() / 常用命名色）
    static func parseCSSColor(_ raw: String) -> UIColor? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty || t == "transparent" || t.hasPrefix("rgba(0, 0, 0, 0") { return nil }
        if t.hasPrefix("#") {
            var hex = String(t.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 8 { hex = String(hex.prefix(6)) }
            guard hex.count == 6, let v = UInt64(hex, radix: 16) else { return nil }
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        if t.hasPrefix("rgb") {
            guard let re = try? NSRegularExpression(pattern: "[0-9]+\\.?[0-9]*") else { return nil }
            let ns = t as NSString
            let vals = re.matches(in: t, range: NSRange(location: 0, length: ns.length))
                .compactMap { Double(ns.substring(with: $0.range)) }
            if vals.count >= 3 {
                func norm(_ x: Double) -> CGFloat { x <= 1.0 ? CGFloat(x) : CGFloat(x / 255.0) }
                let a: CGFloat = vals.count >= 4 ? CGFloat(max(0, min(1, vals[3]))) : 1
                return UIColor(red: norm(vals[0]), green: norm(vals[1]), blue: norm(vals[2]), alpha: a)
            }
        }
        let named: [String: UIColor] = ["white": .white, "black": .black,
                                        "red": .red, "blue": .blue, "green": .green,
                                        "orange": .orange, "yellow": .yellow,
                                        "gray": .gray, "grey": .gray]
        return named[t]
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 首次加载完成：只弹一条精简就绪提示（网页内自绘提示已移除，不会双份）
        if !didAnnounceReady {
            didAnnounceReady = true
            announceReady()
        }
        // 页面加载完成：提取标题与主题色，标题栏自动跟随变色；同时刷新导航按钮状态
        refreshNavAvailability()
        webView.evaluateJavaScript(Self.themeJS) { [weak self] res, _ in
            guard let self = self else { return }
            var title = ""
            var colorStr: String?
            if let s = res as? String,
               let data = s.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                title = dict["t"] as? String ?? ""
                colorStr = dict["c"] as? String
            }
            DispatchQueue.main.async {
                self.pageTitle = title
                self.barUIColor = colorStr.flatMap(Self.parseCSSColor)
            }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // 每次页面开始加载时刷新手机定位（节流），确保坐标随人移动更新
        refreshDeviceLocation()
        // 模拟定位生效时：本次加载的坐标有变化就提示，并为下次加载重新随机浮动
        if locationSettings.effectiveMode != "off" {
            announceInjectedLocation()
            rebuildScripts()
        }
        // 同步当前地址给地址栏
        if let s = webView.url?.absoluteString {
            DispatchQueue.main.async { self.currentURLString = s }
        }
    }

    /// 当前注入坐标与上次提示的不同（≥约1米）则弹气泡；随机浮动开启时每次页面加载都会提示新坐标
    private func announceInjectedLocation() {
        guard let f = injectedFake, f.enabled else { return }
        let prev = lastLocToastCoord
        let moved = prev == nil
            || abs(f.lat - prev!.lat) > 1e-5
            || abs(f.lng - prev!.lng) > 1e-5
        lastLocToastCoord = (f.lat, f.lng)
        if moved {
            showToast(String(format: "定位已更新 %.4f, %.4f", f.lat, f.lng), kind: .locate)
        }
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
          return '已解锁 ' + (n + (s.unlocked || 0)) + ' 个上传框' +
            (s.fakeLocation && s.fakeLocation !== 'off' ? ' · 定位已模拟' : '');
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                let text = (result as? String) ?? "脚本未就绪"
                self?.showToast(text)
            }
        }
    }

    /// 应用内轻提示：统一走底部气泡（同一时刻只存在一条，新提示直接替换旧的）
    func showToast(_ text: String, kind: ToastKind = .info) {
        quickStats = text
        statusLine = text
        toast = ToastMessage(text, kind: kind)
    }

    /// 清除全部网站数据（缓存/Cookie/localStorage 等），会丢失登录态
    func clearAllCache() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types,
                                                modifiedSince: Date(timeIntervalSince1970: 0)) { [weak self] in
            DispatchQueue.main.async {
                self?.webView.reload()
                self?.showToast("已清除全部缓存", kind: .success)
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
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            let text = (result as? String) ?? ""
            DispatchQueue.main.async {
                guard let self = self else { return }
                if text.contains("没有 file input") {
                    self.showToast("本页未发现上传框")
                    return
                }
                let lines = text.split(separator: "\n")
                let unlocked = lines.filter { $0.contains("[已解锁]") }.count
                let locked = lines.count - unlocked
                if locked > 0 {
                    self.showToast("\(locked) 个上传框仍在锁定", kind: .warning)
                } else {
                    self.showToast("已解锁 \(unlocked) 个上传框", kind: .success)
                }
            }
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
