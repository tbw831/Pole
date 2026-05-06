import Foundation

/// 赛道布局 SVG —— 数据源 julesr0y/f1-circuits-svg(black-outline 风格,黑色描边),
/// 78 个赛道含历史。F1 全覆盖,MotoGP/WSBK 共享 ~50%。
///
/// URL 解析顺序:
///  1. main bundle Resources/CircuitMaps/{slug}.svg(用户在 Mac 端把目录加进 Xcode target)
///  2. main bundle 根目录的 {slug}.svg(扁平添加方式)
///  3. jsdelivr CDN 远程 fallback(`https://cdn.jsdelivr.net/gh/...`,国内访问稳定)
public nonisolated enum CircuitMap {
    private static let cdnBase = "https://cdn.jsdelivr.net/gh/julesr0y/f1-circuits-svg/circuits/minimal/black-outline"

    /// 给定 slug 返回 SVG URL。
    public static func url(slug: String) -> URL? {
        if let local = Bundle.main.url(
            forResource: slug, withExtension: "svg", subdirectory: "CircuitMaps"
        ) {
            return local
        }
        if let local = Bundle.main.url(forResource: slug, withExtension: "svg") {
            return local
        }
        return URL(string: "\(cdnBase)/\(slug).svg")
    }

    // MARK: - F1

    /// F1 raceName 关键字 → julesr0y slug。当代 24 GP 全覆盖。
    public static func slugForF1(raceName: String) -> String? {
        let n = raceName.lowercased()
        if n.contains("bahrain")             { return "bahrain-3" }
        if n.contains("saudi")               { return "jeddah-1" }
        if n.contains("australian")          { return "melbourne-2" }
        if n.contains("japanese")            { return "suzuka-2" }
        if n.contains("chinese")             { return "shanghai-1" }
        if n.contains("miami")               { return "miami-1" }
        if n.contains("emilia") || n.contains("imola") { return "imola-3" }
        if n.contains("monaco")              { return "monaco-6" }
        if n.contains("madring")             { return "madring-1" }
        if n.contains("spanish")             { return "catalunya-6" }
        if n.contains("canadian")            { return "montreal-6" }
        if n.contains("austrian")            { return "spielberg-3" }
        if n.contains("british")             { return "silverstone-8" }
        if n.contains("hungarian")           { return "hungaroring-3" }
        if n.contains("belgian")             { return "spa-francorchamps-4" }
        if n.contains("dutch")               { return "zandvoort-5" }
        if n.contains("italian")             { return "monza-7" }
        if n.contains("azerbaijan")          { return "baku-1" }
        if n.contains("singapore")           { return "marina-bay-4" }
        if n.contains("united states") || n.contains("austin") { return "austin-1" }
        if n.contains("mexican") || n.contains("mexico city") { return "mexico-city-3" }
        if n.contains("brazilian") || n.contains("são paulo") || n.contains("sao paulo") { return "interlagos-2" }
        if n.contains("las vegas")           { return "las-vegas-1" }
        if n.contains("qatar")               { return "lusail-1" }
        if n.contains("abu dhabi")           { return "yas-marina-2" }
        return nil
    }

    // MARK: - MotoGP / WSBK 共享(由 circuit name + country 推断)

    /// MotoGP/WSBK 用 — 共享 F1 赛道的优先复用,~50% 命中。
    public static func slug(forCircuitName name: String, country: String) -> String? {
        let n = name.lowercased()
        let c = country.lowercased()
        // 共享 F1 赛道:
        if n.contains("austin") || n.contains("circuit of the americas") { return "austin-1" }
        if n.contains("lusail") || c.contains("qat") || c.contains("qatar") { return "lusail-1" }
        if n.contains("mugello")                                 { return "mugello-1" }
        if n.contains("catalunya") || n.contains("barcelona")    { return "catalunya-6" }
        if n.contains("silverstone")                             { return "silverstone-8" }
        if n.contains("bugatti") || (n.contains("le mans") && (c.contains("fra") || c.contains("france"))) { return "bugatti-1" }
        if n.contains("sepang")                                  { return "sepang-1" }
        if n.contains("portimao") || n.contains("algarve")       { return "portimao-1" }
        if n.contains("indianapolis")                            { return "indianapolis-2" }
        if n.contains("donington")                               { return "donington-1" }
        if n.contains("magny")                                   { return "magny-cours-3" }
        if n.contains("estoril")                                 { return "estoril-2" }
        if n.contains("jerez")                                   { return "jerez-2" }
        if n.contains("monza")                                   { return "monza-7" }
        if n.contains("interlagos")                              { return "interlagos-2" }
        if n.contains("imola")                                   { return "imola-3" }
        // MotoGP/WSBK 独有(julesr0y 没有,以后可补):misano / aragon / assen / sachsenring /
        // brno / phillip-island / valencia(cheste) / termas / buriram / most / cremona
        return nil
    }
}
