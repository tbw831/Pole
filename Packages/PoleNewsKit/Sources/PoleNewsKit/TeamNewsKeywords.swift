import Foundation

/// 车队/厂商 → 中英文 keyword 别名映射。
/// 用 constructor / team / builder 的 raw name(lowercased)做 lookup。
public enum TeamNewsKeywords {
    /// 给定原始车队/厂商名,返回包含中英文别名的 keyword 数组(用于 RSS 过滤)。
    public static func keywords(for rawName: String) -> [String] {
        let lc = rawName.lowercased()
        var keys: Set<String> = [rawName]

        // F1 中文别名
        if lc.contains("red bull") || lc == "rb" || lc.contains("racing bulls") {
            keys.insert("Red Bull"); keys.insert("红牛"); keys.insert("RBR"); keys.insert("Verstappen"); keys.insert("维斯塔潘")
        }
        if lc.contains("mercedes") {
            keys.insert("Mercedes"); keys.insert("梅赛德斯"); keys.insert("Hamilton"); keys.insert("Russell"); keys.insert("汉密尔顿")
        }
        if lc.contains("ferrari") {
            keys.insert("Ferrari"); keys.insert("法拉利"); keys.insert("Leclerc"); keys.insert("勒克莱尔")
        }
        if lc.contains("mclaren") {
            keys.insert("McLaren"); keys.insert("迈凯伦"); keys.insert("Norris"); keys.insert("Piastri"); keys.insert("诺里斯")
        }
        if lc.contains("aston martin") {
            keys.insert("Aston Martin"); keys.insert("阿斯顿马丁"); keys.insert("Alonso"); keys.insert("阿隆索")
        }
        if lc.contains("alpine") {
            keys.insert("Alpine"); keys.insert("阿尔派"); keys.insert("Gasly")
        }
        if lc.contains("williams") {
            keys.insert("Williams"); keys.insert("威廉姆斯"); keys.insert("Albon")
        }
        if lc.contains("sauber") || lc.contains("stake") || lc.contains("kick") {
            keys.insert("Sauber"); keys.insert("Stake"); keys.insert("索伯")
        }
        if lc.contains("haas") {
            keys.insert("Haas"); keys.insert("哈斯"); keys.insert("Bearman")
        }

        // MotoGP 厂商
        if lc.contains("aprilia") {
            keys.insert("Aprilia"); keys.insert("阿普利亚")
        }
        if lc.contains("ducati") {
            keys.insert("Ducati"); keys.insert("杜卡迪")
        }
        if lc.contains("yamaha") {
            keys.insert("Yamaha"); keys.insert("雅马哈")
        }
        if lc.contains("honda") {
            keys.insert("Honda"); keys.insert("本田")
        }
        if lc.contains("ktm") {
            keys.insert("KTM")
        }
        if lc.contains("kawasaki") {
            keys.insert("Kawasaki"); keys.insert("川崎")
        }
        if lc.contains("triumph") {
            keys.insert("Triumph"); keys.insert("凯旋")
        }
        if lc.contains("mv agusta") {
            keys.insert("MV Agusta"); keys.insert("奥古斯塔")
        }
        if lc.contains("zxmoto") {
            keys.insert("ZXMOTO"); keys.insert("张雪"); keys.insert("张雪机车")
        }

        return Array(keys)
    }
}
