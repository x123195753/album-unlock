import Foundation

enum AlbumUnlockScript {
    static var source: String {
        guard let url = Bundle.main.url(forResource: "AlbumUnlock", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return js
    }
}
