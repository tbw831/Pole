import Foundation

/// 全局中文显示 mapping —— 各 series 的 race / round 名、country code、status 等。
/// model 的 headline / subheadline 在拼接显示前先过这里。
///
/// `nonisolated` —— 让 nonisolated 的 F1Race / MotoGPRound / WSBKRound / FERound 等
/// 领域类型能在 headline / subheadline computed property 里直接调用。底层只读
/// L10n.effective(也是 nonisolated)+ 静态 dict,无任何 MainActor 状态。
public nonisolated enum Localization {

    // MARK: - F1 Grand Prix(24 GP)

    /// "Bahrain Grand Prix" → 中文"巴林大奖赛" / 英文 pass-through。
    /// 覆盖范围:当代 24 GP + 2026 改名(Madrid 等)+ 历史 GP(2010 后偶尔出现)+ COVID 临时站。
    public static func f1RaceName(_ raceName: String) -> String {
        if L10n.effective == .en { return raceName }
        let n = raceName.lowercased()
        // 当代 24 GP(命中优先)
        if n.contains("bahrain")             { return "巴林大奖赛" }
        if n.contains("saudi")               { return "沙特阿拉伯大奖赛" }
        if n.contains("australian")          { return "澳大利亚大奖赛" }
        if n.contains("japanese")            { return "日本大奖赛" }
        if n.contains("chinese")             { return "中国大奖赛" }
        if n.contains("miami")               { return "迈阿密大奖赛" }
        if n.contains("emilia") || n.contains("imola") { return "艾米利亚-罗马涅大奖赛" }
        if n.contains("monaco")              { return "摩纳哥大奖赛" }
        if n.contains("madring") || n.contains("madrid") { return "马德里大奖赛" }
        if n.contains("barcelona") || n.contains("catalu") || n.contains("catalonia") { return "巴塞罗那大奖赛" }
        if n.contains("spanish")             { return "西班牙大奖赛" }
        if n.contains("canadian")            { return "加拿大大奖赛" }
        if n.contains("austrian")            { return "奥地利大奖赛" }
        if n.contains("british")             { return "英国大奖赛" }
        if n.contains("hungarian")           { return "匈牙利大奖赛" }
        if n.contains("belgian")             { return "比利时大奖赛" }
        if n.contains("dutch")               { return "荷兰大奖赛" }
        if n.contains("italian") || n.contains("italy") { return "意大利大奖赛" }
        if n.contains("azerbaijan")          { return "阿塞拜疆大奖赛" }
        if n.contains("singapore")           { return "新加坡大奖赛" }
        if n.contains("united states") || n.contains("usa")   { return "美国大奖赛" }
        if n.contains("mexican") || n.contains("mexico city") { return "墨西哥城大奖赛" }
        if n.contains("brazilian") || n.contains("são paulo") || n.contains("sao paulo") { return "圣保罗大奖赛" }
        if n.contains("las vegas")           { return "拉斯维加斯大奖赛" }
        if n.contains("qatar")               { return "卡塔尔大奖赛" }
        if n.contains("abu dhabi")           { return "阿布扎比大奖赛" }
        // 历史/曾用 GP(jolpica 跨季查询时会返回)
        if n.contains("french")              { return "法国大奖赛" }
        if n.contains("german")              { return "德国大奖赛" }
        if n.contains("russian")             { return "俄罗斯大奖赛" }
        if n.contains("korean")              { return "韩国大奖赛" }
        if n.contains("indian")              { return "印度大奖赛" }
        if n.contains("turkish")             { return "土耳其大奖赛" }
        if n.contains("malaysian")           { return "马来西亚大奖赛" }
        if n.contains("south african")       { return "南非大奖赛" }
        if n.contains("argentine")           { return "阿根廷大奖赛" }
        if n.contains("portuguese")          { return "葡萄牙大奖赛" }
        if n.contains("european")            { return "欧洲大奖赛" }
        // 2020 covid 临时 + 早期特殊
        if n.contains("70th anniversary")    { return "F1 70 周年大奖赛" }
        if n.contains("sakhir")              { return "萨基尔大奖赛" }
        if n.contains("eifel")               { return "艾菲尔大奖赛" }
        if n.contains("tuscan")              { return "托斯卡纳大奖赛" }
        if n.contains("styrian")             { return "施泰尔马克大奖赛" }
        if n.contains("pacific")             { return "太平洋大奖赛" }
        if n.contains("caesars")             { return "凯撒宫大奖赛" }
        if n.contains("detroit")             { return "底特律大奖赛" }
        if n.contains("dallas")              { return "达拉斯大奖赛" }
        if n.contains("luxembourg")          { return "卢森堡大奖赛" }
        if n.contains("swiss")               { return "瑞士大奖赛" }
        return raceName
    }

    // MARK: - MotoGP Round(基于 round.name + IOC country code)

    /// "GRAND PRIX DE FRANCE" / IOC code "FRA" → 中文"法国大奖赛" / 英文 Title Case
    public static func motoGPRoundName(rawName: String, countryCode: String) -> String {
        if L10n.effective == .en {
            return rawName.localizedCapitalized
        }
        // 站点级特殊覆盖(优先于 country code,因为同 country 多站时 country code 会重复)
        let n = rawName.lowercased()
        if n.contains("aragon") || n.contains("aragón")        { return "阿拉贡大奖赛" }
        if n.contains("catalu") || n.contains("catalonia") || n.contains("catalan") { return "加泰罗尼亚大奖赛" }
        if n.contains("emilia") || n.contains("misano") || n.contains("san marino") { return "圣马力诺大奖赛" }
        if n.contains("mugello")                                { return "穆杰罗大奖赛" }
        if n.contains("americas") || n.contains("america")      { return "美洲大奖赛" }
        if n.contains("assen") || n.contains("netherlands")     { return "荷兰 TT 大奖赛" }
        if n.contains("solidarity")                             { return "团结大奖赛" }
        if n.contains("kazakhstan")                             { return "哈萨克斯坦大奖赛" }
        if n.contains("mandalika") || n.contains("indonesia")   { return "印度尼西亚大奖赛" }
        if n.contains("portuguese") || n.contains("portimão") || n.contains("portimao") { return "葡萄牙大奖赛" }
        if n.contains("valencia") || n.contains("comunitat")    { return "瓦伦西亚大奖赛" }
        if n.contains("thailand") || n.contains("buriram")      { return "泰国大奖赛" }
        // raceName 国家关键字兜底(country code 异常 / 非 IOC 时仍能命中)。
        // 必须在 country code lookup 之前 — Pulselive 偶尔给 "Grand Prix Of Spain" 但 country code 不规范。
        if n.contains("spain") || n.contains("spanish") || n.contains("jerez") { return "西班牙大奖赛" }
        if n.contains("france") || n.contains("french") || n.contains("le mans") { return "法国大奖赛" }
        if n.contains("italy") || n.contains("italian")        { return "意大利大奖赛" }
        if n.contains("british") || n.contains("britain") || n.contains("united kingdom") || n.contains("silverstone") { return "英国大奖赛" }
        if n.contains("german") || n.contains("sachsenring")   { return "德国大奖赛" }
        if n.contains("austria") || n.contains("red bull ring") { return "奥地利大奖赛" }
        if n.contains("hungar") || n.contains("balaton")       { return "匈牙利大奖赛" }
        if n.contains("czech") || n.contains("brno")           { return "捷克大奖赛" }
        if n.contains("japan")                                  { return "日本大奖赛" }
        if n.contains("australia") || n.contains("phillip island") { return "澳大利亚大奖赛" }
        if n.contains("argentin") || n.contains("termas")      { return "阿根廷大奖赛" }
        if n.contains("brazil") || n.contains("goiania")       { return "巴西大奖赛" }
        if n.contains("malaysia") || n.contains("sepang")      { return "马来西亚大奖赛" }
        if n.contains("qatar") || n.contains("losail") || n.contains("lusail") { return "卡塔尔大奖赛" }
        if n.contains("turk") || n.contains("istanbul")        { return "土耳其大奖赛" }
        if n.contains("china") || n.contains("shanghai")       { return "中国大奖赛" }
        if n.contains("india")                                  { return "印度大奖赛" }
        // 然后 country code
        if let country = ChineseCountry.fromIOC(countryCode) {
            return "\(country)大奖赛"
        }
        return rawName.localizedCapitalized
    }

    // MARK: - WSBK / WSSP Round

    /// "Motul Hungarian Round" / IOC "HUN" → 中文"匈牙利分站" / 英文剥赞助商
    public static func wsbkRoundName(rawName: String, countryCode: String) -> String {
        if L10n.effective == .en {
            // 英文剥赞助商前缀(Motul/Pirelli/Acerbis)
            let cleaned = rawName.replacingOccurrences(
                of: #"^(Motul|Pirelli|Acerbis|MotulFIM|Prosecco)\s*"#,
                with: "", options: [.regularExpression, .caseInsensitive]
            )
            return cleaned.localizedCapitalized
        }
        // 站点级特殊覆盖(同国多站时优先,如 Aragon vs Jerez 都在西班牙)
        let n = rawName.lowercased()
        if n.contains("aragon") || n.contains("aragón")        { return "阿拉贡分站" }
        if n.contains("catalu") || n.contains("catalonia")     { return "加泰罗尼亚分站" }
        if n.contains("jerez") || n.contains("andalu")         { return "赫雷斯分站" }
        if n.contains("misano") || n.contains("emilia") || n.contains("san marino") { return "圣马力诺分站" }
        if n.contains("imola")                                  { return "艾米利亚-罗马涅分站" }
        if n.contains("most")                                   { return "莫斯特分站" }
        if n.contains("estoril")                                { return "葡萄牙分站" }
        if n.contains("magny") || n.contains("magny-cours")     { return "马尼库尔分站" }
        if n.contains("assen")                                  { return "阿森分站" }
        if n.contains("portimão") || n.contains("portimao")     { return "葡萄牙分站" }
        if n.contains("balaton")                                { return "巴拉顿分站" }
        if n.contains("mandalika")                              { return "印度尼西亚分站" }
        if n.contains("phillip island")                         { return "菲利普岛分站" }
        if n.contains("cremona")                                { return "克雷莫纳分站" }
        // raceName 国家关键字兜底
        if n.contains("spain") || n.contains("spanish")        { return "西班牙分站" }
        if n.contains("french") || n.contains("france")        { return "法国分站" }
        if n.contains("italy") || n.contains("italian")        { return "意大利分站" }
        if n.contains("british") || n.contains("united kingdom") { return "英国分站" }
        if n.contains("german")                                 { return "德国分站" }
        if n.contains("austra")                                 { return "澳大利亚分站" }
        if n.contains("argentin")                               { return "阿根廷分站" }
        if n.contains("portuguese")                             { return "葡萄牙分站" }
        if n.contains("hungar")                                 { return "匈牙利分站" }
        if n.contains("czech")                                  { return "捷克分站" }
        // 然后 country code
        if let country = ChineseCountry.fromIOC(countryCode) {
            return "\(country)分站"
        }
        // fallback 解析 raw(剥赞助商前缀 + Round → 分站)
        let cleaned = rawName.replacingOccurrences(
            of: #"^(Motul|Pirelli|Acerbis|MotulFIM|Prosecco|Aragon)\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return cleaned.replacingOccurrences(of: "Round", with: "分站")
    }

    // MARK: - FE E-Prix

    /// "2025 Google Cloud São Paulo E-Prix" → 中文"圣保罗大奖赛" / 英文剥年份+赞助商
    /// double-header 周末 race 1/2 后缀(Pulselive 偶尔附 "Race 1/2")会被保留区分两站。
    /// 中文不加 "E" 前缀(FE 列表上下文就是 FE,不会跟 F1 混淆)。
    public static func feRaceName(_ rawName: String) -> String {
        // 剥年份前缀 + 赞助商
        var cleaned = rawName.replacingOccurrences(of: #"^\d{4}\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"^(Google Cloud|Hankook|ABB|Julius Baer|SABIC|DHL|Tata Communications|CUPRA)\s*"#,
                                               with: "", options: [.regularExpression, .caseInsensitive])

        // 提取 "Race 1" / "Round 2" 等末尾编号后缀(double-header 周末用,保留区分)
        var raceSuffix: String? = nil
        if let match = cleaned.range(of: #"\s*[-–]?\s*(Race|Round)\s*(\d+)\s*$"#,
                                      options: [.regularExpression, .caseInsensitive]) {
            let captured = String(cleaned[match])
            let digits = captured.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)
            if !digits.isEmpty {
                raceSuffix = L10n.effective == .en ? "Race \(digits)" : "第 \(digits) 场"
            }
            cleaned.removeSubrange(match)
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }

        if L10n.effective == .en {
            // "São Paulo E-Prix" + " · Race 2"(若有)
            return raceSuffix.map { "\(cleaned) · \($0)" } ?? cleaned
        }
        cleaned = cleaned.replacingOccurrences(of: " E-Prix", with: "", options: .caseInsensitive)
                         .trimmingCharacters(in: .whitespaces)
        let cityPart: String
        if let city = chineseCity(cleaned) {
            cityPart = "\(city)大奖赛"
        } else {
            cityPart = "\(cleaned)大奖赛"
        }
        return raceSuffix.map { "\(cityPart) · \($0)" } ?? cityPart
    }

    /// FE 常见城市英→中。按 lowercase + contains 匹配,容错赞助商前缀 / 大小写差异。
    private static func chineseCity(_ name: String) -> String? {
        let n = name.lowercased()
        // ----- 当前赛历(2024/2025/2026) -----
        if n.contains("são paulo") || n.contains("sao paulo") { return "圣保罗" }
        if n.contains("mexico city")        { return "墨西哥城" }
        if n.contains("jeddah")             { return "吉达" }
        if n.contains("cape town")          { return "开普敦" }
        if n.contains("miami")              { return "迈阿密" }
        if n.contains("berlin")             { return "柏林" }
        if n.contains("tokyo")              { return "东京" }
        if n.contains("shanghai")           { return "上海" }
        if n.contains("monaco")             { return "摩纳哥" }
        if n.contains("jakarta")            { return "雅加达" }
        if n.contains("portland")           { return "波特兰" }
        if n.contains("rome")               { return "罗马" }
        if n.contains("london")             { return "伦敦" }
        if n.contains("diriyah") || n.contains("ad diriyah") { return "迪里耶" }
        if n.contains("hyderabad")          { return "海得拉巴" }
        if n.contains("seoul")              { return "首尔" }
        if n.contains("new york")           { return "纽约" }
        if n.contains("misano")             { return "米萨诺" }
        if n.contains("madrid")             { return "马德里" }
        if n.contains("riyadh")             { return "利雅得" }
        // ----- 历史赛站(用户切到旧赛季会用上) -----
        if n.contains("marrakesh") || n.contains("marrakech") { return "马拉喀什" }
        if n.contains("sanya")              { return "三亚" }
        if n.contains("hong kong")          { return "香港" }
        if n.contains("putrajaya")          { return "普特拉贾亚" }
        if n.contains("long beach")         { return "长滩" }
        if n.contains("bern")               { return "伯尔尼" }
        if n.contains("zürich") || n.contains("zurich") { return "苏黎世" }
        if n.contains("punta del este")     { return "埃斯特角" }
        if n.contains("beijing")            { return "北京" }
        if n.contains("paris")              { return "巴黎" }
        if n.contains("valencia")           { return "瓦伦西亚" }
        if n.contains("buenos aires")       { return "布宜诺斯艾利斯" }
        if n.contains("santiago")           { return "圣地亚哥" }
        if n.contains("bangkok")            { return "曼谷" }
        if n.contains("vancouver")          { return "温哥华" }
        if n.contains("moscow")             { return "莫斯科" }
        if n.contains("dubai")              { return "迪拜" }
        return nil
    }
}

// MARK: - 国家代码 / 国名 双语化

public nonisolated enum ChineseCountry {
    /// IOC 三字母 / ISO3 → 国名(中英自动切换)。
    public static func fromIOC(_ code: String) -> String? {
        let c = code.uppercased()
        if L10n.effective == .en { return englishFromIOC(c) }
        let m: [String: String] = [
            "AUS": "澳大利亚", "AUT": "奥地利", "ARG": "阿根廷",
            "BHR": "巴林", "BEL": "比利时", "BRA": "巴西", "BUL": "保加利亚", "BGR": "保加利亚",
            "CAN": "加拿大", "CHN": "中国", "CHI": "智利", "COL": "哥伦比亚", "CZE": "捷克", "CRO": "克罗地亚",
            "DEN": "丹麦", "DNK": "丹麦", "DEU": "德国", "GER": "德国",
            "ESP": "西班牙", "EST": "爱沙尼亚",
            "FIN": "芬兰", "FRA": "法国",
            "GRE": "希腊", "GBR": "英国", "ENG": "英国",
            "HKG": "中国香港", "HUN": "匈牙利",
            "IND": "印度", "IDN": "印度尼西亚", "INA": "印度尼西亚", "IRL": "爱尔兰", "IRE": "爱尔兰",
            "ITA": "意大利", "ISR": "以色列",
            "JPN": "日本", "JER": "泽西岛",
            "KOR": "韩国",
            "LUX": "卢森堡",
            "MEX": "墨西哥", "MCO": "摩纳哥", "MON": "摩纳哥", "MAS": "马来西亚", "MYS": "马来西亚",
            "MAR": "摩洛哥",
            "NED": "荷兰", "NLD": "荷兰", "NOR": "挪威", "NZL": "新西兰",
            "POL": "波兰", "POR": "葡萄牙", "PRT": "葡萄牙", "PHI": "菲律宾", "PHL": "菲律宾",
            "QAT": "卡塔尔",
            "RSA": "南非", "ZAF": "南非", "ROU": "罗马尼亚", "RUS": "俄罗斯",
            "SAU": "沙特阿拉伯", "KSA": "沙特阿拉伯", "SGP": "新加坡", "SIN": "新加坡",
            "SUI": "瑞士", "CHE": "瑞士", "SWE": "瑞典", "SCO": "苏格兰",
            "THA": "泰国", "TWN": "中国台湾", "TPE": "中国台湾", "TUR": "土耳其",
            "UAE": "阿联酋", "ARE": "阿联酋", "USA": "美国", "URU": "乌拉圭", "URY": "乌拉圭", "UKR": "乌克兰",
            "VEN": "委内瑞拉", "VIE": "越南", "VNM": "越南",
            "WAL": "威尔士",
            // 一些 worldsbk 用的常见 code
            "RSM": "圣马力诺", "SMR": "圣马力诺",
            "ARA": "阿拉贡",
        ]
        return m[c]
    }

    /// IOC → 英文国名(en 模式用,把 "BHR" 转 "Bahrain")
    private static func englishFromIOC(_ code: String) -> String? {
        let m: [String: String] = [
            "AUS": "Australia", "AUT": "Austria", "ARG": "Argentina",
            "BHR": "Bahrain", "BEL": "Belgium", "BRA": "Brazil", "BUL": "Bulgaria", "BGR": "Bulgaria",
            "CAN": "Canada", "CHN": "China", "CHI": "Chile", "COL": "Colombia", "CZE": "Czech Republic",
            "CRO": "Croatia",
            "DEN": "Denmark", "DNK": "Denmark", "DEU": "Germany", "GER": "Germany",
            "ESP": "Spain", "EST": "Estonia",
            "FIN": "Finland", "FRA": "France",
            "GRE": "Greece", "GBR": "United Kingdom", "ENG": "England",
            "HKG": "Hong Kong", "HUN": "Hungary",
            "IND": "India", "IDN": "Indonesia", "INA": "Indonesia", "IRL": "Ireland", "IRE": "Ireland",
            "ITA": "Italy", "ISR": "Israel",
            "JPN": "Japan", "JER": "Jersey",
            "KOR": "South Korea",
            "LUX": "Luxembourg",
            "MEX": "Mexico", "MCO": "Monaco", "MON": "Monaco", "MAS": "Malaysia", "MYS": "Malaysia",
            "MAR": "Morocco",
            "NED": "Netherlands", "NLD": "Netherlands", "NOR": "Norway", "NZL": "New Zealand",
            "POL": "Poland", "POR": "Portugal", "PRT": "Portugal",
            "PHI": "Philippines", "PHL": "Philippines",
            "QAT": "Qatar",
            "RSA": "South Africa", "ZAF": "South Africa", "ROU": "Romania", "RUS": "Russia",
            "SAU": "Saudi Arabia", "KSA": "Saudi Arabia", "SGP": "Singapore", "SIN": "Singapore",
            "SUI": "Switzerland", "CHE": "Switzerland", "SWE": "Sweden", "SCO": "Scotland",
            "THA": "Thailand", "TWN": "Taiwan", "TPE": "Taiwan", "TUR": "Turkey",
            "UAE": "UAE", "ARE": "UAE", "USA": "USA", "URU": "Uruguay", "URY": "Uruguay", "UKR": "Ukraine",
            "VEN": "Venezuela", "VIE": "Vietnam", "VNM": "Vietnam",
            "WAL": "Wales",
            "RSM": "San Marino", "SMR": "San Marino",
            "ARA": "Aragon",
        ]
        return m[code]
    }

    /// ISO 2 字母("GB" "IT")→ 国名(中英自动切换)
    public static func fromISO2(_ code: String) -> String? {
        let c = code.uppercased()
        if L10n.effective == .en {
            // 英文模式直接返简单 mapping
            let m: [String: String] = [
                "AU": "Australia", "AT": "Austria", "AR": "Argentina",
                "BH": "Bahrain", "BE": "Belgium", "BR": "Brazil",
                "CA": "Canada", "CN": "China", "CL": "Chile", "CO": "Colombia", "CZ": "Czech Republic",
                "DK": "Denmark", "DE": "Germany",
                "ES": "Spain", "FR": "France", "FI": "Finland",
                "GB": "United Kingdom",
                "HU": "Hungary",
                "IN": "India", "ID": "Indonesia", "IE": "Ireland", "IT": "Italy",
                "JP": "Japan", "KR": "South Korea",
                "MX": "Mexico", "MC": "Monaco", "MY": "Malaysia", "MA": "Morocco",
                "NL": "Netherlands", "NO": "Norway", "NZ": "New Zealand",
                "PL": "Poland", "PT": "Portugal",
                "QA": "Qatar",
                "ZA": "South Africa", "RO": "Romania", "RU": "Russia",
                "SA": "Saudi Arabia", "SG": "Singapore", "CH": "Switzerland", "SE": "Sweden",
                "TH": "Thailand", "TW": "Taiwan", "TR": "Turkey",
                "AE": "UAE", "US": "USA",
            ]
            return m[c]
        }
        let m: [String: String] = [
            "AU": "澳大利亚", "AT": "奥地利", "AR": "阿根廷",
            "BH": "巴林", "BE": "比利时", "BR": "巴西", "BG": "保加利亚",
            "CA": "加拿大", "CN": "中国", "CL": "智利", "CO": "哥伦比亚", "CZ": "捷克",
            "DK": "丹麦", "DE": "德国",
            "ES": "西班牙", "EE": "爱沙尼亚",
            "FI": "芬兰", "FR": "法国",
            "GR": "希腊", "GB": "英国",
            "HK": "中国香港", "HU": "匈牙利",
            "IN": "印度", "ID": "印度尼西亚", "IE": "爱尔兰", "IT": "意大利", "IL": "以色列",
            "JP": "日本",
            "KR": "韩国",
            "MX": "墨西哥", "MC": "摩纳哥", "MY": "马来西亚", "MA": "摩洛哥",
            "NL": "荷兰", "NO": "挪威", "NZ": "新西兰",
            "PL": "波兰", "PT": "葡萄牙", "PH": "菲律宾",
            "QA": "卡塔尔",
            "ZA": "南非", "RO": "罗马尼亚", "RU": "俄罗斯",
            "SA": "沙特阿拉伯", "SG": "新加坡", "CH": "瑞士", "SE": "瑞典",
            "TH": "泰国", "TW": "中国台湾", "TR": "土耳其",
            "AE": "阿联酋", "US": "美国", "UY": "乌拉圭", "UA": "乌克兰",
            "VE": "委内瑞拉", "VN": "越南",
        ]
        return m[c]
    }

    /// F1 nationality 形容词("British"/"Italian")→ 国名(中英自动切换;英文 pass-through)
    public static func fromF1Nationality(_ nat: String) -> String? {
        if L10n.effective == .en { return nat }
        let n = nat.lowercased()
        let m: [String: String] = [
            "british": "英国", "english": "英国", "scottish": "英国", "welsh": "英国",
            "american": "美国", "australian": "澳大利亚", "austrian": "奥地利",
            "argentine": "阿根廷", "argentinian": "阿根廷",
            "belgian": "比利时", "brazilian": "巴西", "bulgarian": "保加利亚",
            "canadian": "加拿大", "chinese": "中国", "colombian": "哥伦比亚",
            "czech": "捷克", "danish": "丹麦", "dutch": "荷兰",
            "estonian": "爱沙尼亚",
            "finnish": "芬兰", "french": "法国",
            "german": "德国",
            "hungarian": "匈牙利",
            "indian": "印度", "indonesian": "印度尼西亚", "irish": "爱尔兰", "italian": "意大利",
            "japanese": "日本",
            "korean": "韩国",
            "liechtensteiner": "列支敦士登",
            "malaysian": "马来西亚", "mexican": "墨西哥",
            "monégasque": "摩纳哥", "monegasque": "摩纳哥",
            "new zealander": "新西兰", "norwegian": "挪威",
            "polish": "波兰", "portuguese": "葡萄牙",
            "rhodesian": "津巴布韦", "romanian": "罗马尼亚", "russian": "俄罗斯",
            "south african": "南非", "spanish": "西班牙", "swedish": "瑞典", "swiss": "瑞士",
            "thai": "泰国", "turkish": "土耳其",
            "uruguayan": "乌拉圭",
            "venezuelan": "委内瑞拉",
        ]
        return m[n]
    }
}

// MARK: - 比赛结果状态

public nonisolated enum ChineseStatus {
    /// "Finished" / "+1 Lap" / "Engine" / "Accident" → 中英自动切换(英文 pass-through)
    public static func raceStatus(_ status: String) -> String {
        if L10n.effective == .en { return status }
        let s = status.lowercased()
        if s == "finished"                 { return "完赛" }
        if s.hasPrefix("+") && s.contains("lap") {
            // "+1 Lap" / "+2 Laps" → "落后 1 圈"
            let n = s.replacingOccurrences(of: #"[^\d]"#, with: "", options: .regularExpression)
            return n.isEmpty ? status : "落后 \(n) 圈"
        }
        if s.contains("engine")            { return "发动机" }
        if s.contains("accident") || s.contains("collision") { return "事故" }
        if s.contains("spun off")          { return "冲出" }
        if s.contains("retired")           { return "退赛" }
        if s.contains("disqualified")      { return "失格" }
        if s.contains("withdrew")          { return "退出" }
        if s.contains("not classified")    { return "未排名" }
        if s.contains("did not start") || s == "dns" { return "未发车" }
        if s.contains("did not qualify") || s == "dnq" { return "未排到位" }
        if s.contains("brakes")            { return "刹车故障" }
        if s.contains("gearbox")           { return "变速箱" }
        if s.contains("hydraulics")        { return "液压" }
        if s.contains("electrical")        { return "电气故障" }
        if s.contains("transmission")      { return "传动" }
        if s.contains("power unit")        { return "动力单元" }
        if s.contains("suspension")        { return "悬挂" }
        if s.contains("tyre") || s.contains("tire") { return "轮胎" }
        if s.contains("oil leak")          { return "漏油" }
        if s.contains("overheating")       { return "过热" }
        return status
    }
}

// MARK: - 车手 / 车队中文化
//
// 设计:
// - 输入是 model 自带的 raw 串(F1Driver.fullName / MotoGPRider.fullName / F1Constructor.id 等),
//   全部用 lowercase + 关键字匹配,跨数据源大小写差异安全
// - 提供 short(姓 / 简称,List 行紧凑用)和 full(全名,Detail 标题正式用)两个粒度
// - 表里没有的全部 pass-through 原文,不强翻
// - 英文模式直接返原文(剥赞助商前缀的车队名做轻清理)

public nonisolated enum MotorsportNames {

    /// 把 raw 字符串规整为 ASCII lowercase（去重音 + 转小写）以做容错匹配。
    /// "Pérez" → "perez"; "Hülkenberg" → "hulkenberg"; "Räikkönen" → "raikkonen"; "Aragón" → "aragon"
    /// 让所有内部 mapping 函数的 `n.contains("perez")` 等 ASCII 字面匹配
    /// 也能命中带重音的西/德/法/北欧语原字符,避免漏译。
    private static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
    }

    // MARK: 车手 — 短名(姓)

    /// 给 List 行用 — F1Driver.displayName / MotoGPRider.displayName 等内部走它。
    public static func driverShortName(rawFullName: String, series: MotorsportSeries) -> String {
        if L10n.effective == .en { return rawFullName }
        let n = normalize(rawFullName)
        let mapped: String? = {
            switch series {
            case .f1:     return f1DriverShort(n)
            case .motogp: return motoGPRiderShort(n)
            case .wssp:   return wsspRiderShort(n)
            case .fe:     return feDriverShort(n)
            }
        }()
        return mapped ?? rawFullName
    }

    // MARK: 车手 — 全名

    /// 给 Detail 标题用 — F1Driver.displayFullName 等内部走它。
    public static func driverFullName(rawFullName: String, series: MotorsportSeries) -> String {
        if L10n.effective == .en { return rawFullName }
        let n = normalize(rawFullName)
        let mapped: String? = {
            switch series {
            case .f1:     return f1DriverFull(n)
            case .motogp: return motoGPRiderFull(n)
            case .wssp:   return wsspRiderFull(n)
            case .fe:     return feDriverFull(n)
            }
        }()
        return mapped ?? rawFullName
    }

    // MARK: 车队 / 厂商

    /// F1Constructor.displayName / MotoGPTeam.displayName / WSSPBuilder.displayName / FETeam.displayName 内部走它。
    public static func teamName(raw: String, series: MotorsportSeries) -> String {
        if L10n.effective == .en {
            // 英文模式:剥赞助商前缀做轻清理("Monster Energy Yamaha" → "Yamaha";F1 队名一般干净不动)
            return cleanupSponsors(raw)
        }
        let n = normalize(raw)
        let mapped: String? = {
            switch series {
            case .f1:     return f1Team(n)
            case .motogp: return motoGPTeam(n)
            case .wssp:   return wsspBuilder(n)
            case .fe:     return feTeam(n)
            }
        }()
        return mapped ?? raw
    }

    // MARK: - 内部 mapping(按系列)

    // F1 车手 —— driver.fullName 是"Max Verstappen"格式
    private static func f1DriverShort(_ n: String) -> String? {
        // 译名按 CCTV5 / F1 中文官网 / 网易体育 / 新浪赛车主流用法,2025/2026 赛季活跃车手
        if n.contains("verstappen")     { return "维斯塔潘" }
        if n.contains("hamilton")       { return "汉密尔顿" }
        if n.contains("leclerc")        { return "勒克莱尔" }
        if n.contains("russell")        { return "拉塞尔" }
        if n.contains("sainz")          { return "塞恩斯" }
        if n.contains("norris")         { return "诺里斯" }
        if n.contains("piastri")        { return "皮亚斯特里" }
        if n.contains("alonso")         { return "阿隆索" }
        if n.contains("gasly")          { return "加斯利" }
        if n.contains("ocon")           { return "奥康" }
        if n.contains("albon")          { return "阿尔本" }
        if n.contains("hulkenberg") || n.contains("hülkenberg") { return "霍肯伯格" }
        if n.contains("tsunoda")        { return "角田裕毅" }
        if n.contains("zhou")           { return "周冠宇" }
        if n.contains("bottas")         { return "博塔斯" }
        if n.contains("ricciardo")      { return "里卡多" }
        if n.contains("magnussen")      { return "马格努森" }
        if n.contains("sargeant")       { return "萨金特" }
        if n.contains("bearman")        { return "比尔曼" }
        if n.contains("colapinto")      { return "科拉平托" }
        if n.contains("doohan")         { return "杜汉" }
        if n.contains("hadjar")         { return "哈贾尔" }
        if n.contains("lawson")         { return "劳森" }
        if n.contains("bortoleto")      { return "博尔托莱托" }
        if n.contains("lindblad")       { return "林德布拉德" }
        if n.contains("antonelli")      { return "安东内利" }
        if n.contains("stroll")         { return "斯特罗尔" }
        if n.contains("perez")          { return "佩雷兹" }
        if n.contains("vettel")         { return "维特尔" }
        if n.contains("raikkonen") || n.contains("räikkönen") { return "莱科宁" }
        return nil
    }

    private static func f1DriverFull(_ n: String) -> String? {
        if n.contains("verstappen")     { return "马克斯·维斯塔潘" }
        if n.contains("hamilton")       { return "刘易斯·汉密尔顿" }
        if n.contains("leclerc")        { return "夏尔·勒克莱尔" }
        if n.contains("russell")        { return "乔治·拉塞尔" }
        if n.contains("sainz")          { return "卡洛斯·塞恩斯" }
        if n.contains("norris")         { return "兰多·诺里斯" }
        if n.contains("piastri")        { return "奥斯卡·皮亚斯特里" }
        if n.contains("alonso")         { return "费尔南多·阿隆索" }
        if n.contains("gasly")          { return "皮埃尔·加斯利" }
        if n.contains("ocon")           { return "埃斯特班·奥康" }
        if n.contains("albon")          { return "亚历山大·阿尔本" }
        if n.contains("hulkenberg") || n.contains("hülkenberg") { return "尼科·霍肯伯格" }
        if n.contains("tsunoda")        { return "角田裕毅" }
        if n.contains("zhou")           { return "周冠宇" }
        if n.contains("bottas")         { return "瓦尔特利·博塔斯" }
        if n.contains("ricciardo")      { return "丹尼尔·里卡多" }
        if n.contains("magnussen")      { return "凯文·马格努森" }
        if n.contains("sargeant")       { return "罗根·萨金特" }
        if n.contains("bearman")        { return "奥利弗·比尔曼" }
        if n.contains("colapinto")      { return "弗朗哥·科拉平托" }
        if n.contains("doohan")         { return "杰克·杜汉" }
        if n.contains("hadjar")         { return "伊萨克·哈贾尔" }
        if n.contains("lawson")         { return "利亚姆·劳森" }
        if n.contains("bortoleto")      { return "加布里埃尔·博尔托莱托" }
        if n.contains("lindblad")       { return "阿尔维德·林德布拉德" }
        if n.contains("antonelli")      { return "基米·安东内利" }
        if n.contains("stroll")         { return "兰斯·斯特罗尔" }
        if n.contains("perez")          { return "塞尔吉奥·佩雷兹" }
        if n.contains("vettel")         { return "塞巴斯蒂安·维特尔" }
        if n.contains("raikkonen") || n.contains("räikkönen") { return "基米·莱科宁" }
        return nil
    }

    // F1 车队 —— constructor.id 是"red_bull";有些 view 传 name "Red Bull",都按 lowercase 关键字匹配
    private static func f1Team(_ n: String) -> String? {
        if n.contains("red_bull") || n.contains("red bull")     { return "红牛" }
        if n.contains("ferrari")                                { return "法拉利" }
        if n.contains("mercedes")                               { return "梅赛德斯" }
        if n.contains("mclaren")                                { return "迈凯伦" }
        if n.contains("aston")                                  { return "阿斯顿·马丁" }
        if n.contains("alpine")                                 { return "阿尔派" }
        if n.contains("williams")                               { return "威廉姆斯" }
        if n.contains("alphatauri") || n.contains("racing_bulls")
            || n.contains("racing bulls") || n == "rb"          { return "小红牛" }
        if n.contains("kick") && n.contains("sauber")           { return "Kick 索伯" }
        if n.contains("sauber")                                 { return "索伯" }
        if n.contains("alfa")                                   { return "阿尔法·罗密欧" }
        if n.contains("haas")                                   { return "哈斯" }
        return nil
    }

    // MotoGP 车手 —— rider.fullName 是"Marc Marquez"等
    private static func motoGPRiderShort(_ n: String) -> String? {
        // Marquez/Espargaro 兄弟必须先长串后短串,且 short = 全名(否则两兄弟撞名)
        if n.contains("alex marquez") || n.contains("álex marquez")    { return "阿莱士·马奎斯" }
        if n.contains("marc marquez") || n.contains("marc márquez")    { return "马克·马奎斯" }
        if n.contains("bagnaia")        { return "巴尼亚亚" }
        if n.contains("jorge martin") || n.contains("jorge martín") { return "马丁" }
        if n.contains("bastianini")     { return "巴斯蒂亚尼尼" }
        if n.contains("quartararo")     { return "夸尔塔拉罗" }
        if n.contains("di giannantonio") { return "迪贾纳托尼奥" }
        if n.contains("bezzecchi")      { return "贝泽奇" }
        if n.contains("vinales") || n.contains("viñales") { return "维纳莱斯" }
        if n.contains("aleix espargaro") || n.contains("aleix espargaró") { return "阿莱士·埃斯帕加罗" }
        if n.contains("pol espargaro") || n.contains("pol espargaró") { return "波尔·埃斯帕加罗" }
        if n.contains("espargaro") || n.contains("espargaró") { return "埃斯帕加罗" }
        if n.contains("joan mir") || n == "mir" { return "米尔" }
        if n.contains("luca marini")    { return "马里尼" }
        if n.contains("raul fernandez") || n.contains("raúl fernández") { return "劳尔·费尔南德斯" }
        if n.contains("augusto fernandez") || n.contains("augusto fernández") { return "奥古斯托·费尔南德斯" }
        if n.contains("oliveira")       { return "奥利维拉" }
        if n.contains("zarco")          { return "扎尔科" }
        if n.contains("alex rins") || n.contains("álex rins") { return "林斯" }
        if n.contains("nakagami")       { return "中上贵晶" }
        if n.contains("morbidelli")     { return "莫比德利" }
        if n.contains("binder")         { return "宾德" }
        if n.contains("jack miller")    { return "米勒" }
        if n.contains("acosta")         { return "阿科斯塔" }
        if n.contains("ogura")          { return "小椋蓝" }
        if n.contains("aldeguer")       { return "阿尔德盖尔" }
        if n.contains("chantra")        { return "颂吉·詹查" }
        if n.contains("savadori")       { return "萨瓦多里" }
        if n.contains("moreira")        { return "莫雷拉" }
        if n.contains("canet")          { return "卡内特" }
        if n.contains("manuel gonzalez") || n.contains("manuel gonzález") { return "曼努埃尔·冈萨雷斯" }
        if n.contains("aron canet")     { return "阿隆·卡内特" }
        // 经典名将(已退役 / 测试车手 / 历史话题)
        if n.contains("rossi")          { return "罗西" }
        if n.contains("lorenzo")        { return "洛伦索" }
        if n.contains("pedrosa")        { return "佩德罗萨" }
        if n.contains("stoner")         { return "斯通纳" }
        if n.contains("dovizioso")      { return "多维齐奥索" }
        if n.contains("crutchlow")      { return "克拉奇洛" }
        return nil
    }

    private static func motoGPRiderFull(_ n: String) -> String? {
        if n.contains("alex marquez") || n.contains("álex marquez")    { return "阿莱士·马奎斯" }
        if n.contains("marc marquez") || n.contains("marc márquez")    { return "马克·马奎斯" }
        if n.contains("bagnaia")        { return "弗朗西斯科·巴尼亚亚" }
        if n.contains("jorge martin") || n.contains("jorge martín") { return "豪尔赫·马丁" }
        if n.contains("bastianini")     { return "埃内亚·巴斯蒂亚尼尼" }
        if n.contains("quartararo")     { return "法比奥·夸尔塔拉罗" }
        if n.contains("di giannantonio") { return "法比奥·迪贾纳托尼奥" }
        if n.contains("bezzecchi")      { return "马可·贝泽奇" }
        if n.contains("vinales") || n.contains("viñales") { return "马维利克·维纳莱斯" }
        if n.contains("aleix espargaro") || n.contains("aleix espargaró") { return "阿莱士·埃斯帕加罗" }
        if n.contains("pol espargaro") || n.contains("pol espargaró") { return "波尔·埃斯帕加罗" }
        if n.contains("joan mir")       { return "琼·米尔" }
        if n.contains("luca marini")    { return "卢卡·马里尼" }
        if n.contains("raul fernandez") || n.contains("raúl fernández") { return "劳尔·费尔南德斯" }
        if n.contains("augusto fernandez") || n.contains("augusto fernández") { return "奥古斯托·费尔南德斯" }
        if n.contains("oliveira")       { return "米格尔·奥利维拉" }
        if n.contains("zarco")          { return "约翰·扎尔科" }
        if n.contains("alex rins") || n.contains("álex rins") { return "阿莱士·林斯" }
        if n.contains("nakagami")       { return "中上贵晶" }
        if n.contains("morbidelli")     { return "佛朗哥·莫比德利" }
        if n.contains("binder")         { return "布拉德·宾德" }
        if n.contains("jack miller")    { return "杰克·米勒" }
        if n.contains("acosta")         { return "佩德罗·阿科斯塔" }
        if n.contains("ogura")          { return "小椋蓝" }
        if n.contains("aldeguer")       { return "费尔明·阿尔德盖尔" }
        if n.contains("chantra")        { return "颂吉·詹查" }
        if n.contains("savadori")       { return "洛伦佐·萨瓦多里" }
        if n.contains("moreira")        { return "迪奥戈·莫雷拉" }
        if n.contains("manuel gonzalez") || n.contains("manuel gonzález") { return "曼努埃尔·冈萨雷斯" }
        if n.contains("aron canet")     { return "阿隆·卡内特" }
        // 经典名将
        if n.contains("rossi")          { return "瓦伦蒂诺·罗西" }
        if n.contains("lorenzo")        { return "豪尔赫·洛伦索" }
        if n.contains("pedrosa")        { return "丹尼·佩德罗萨" }
        if n.contains("stoner")         { return "凯西·斯通纳" }
        if n.contains("dovizioso")      { return "安德烈亚·多维齐奥索" }
        if n.contains("crutchlow")      { return "卡尔·克拉奇洛" }
        return nil
    }

    // MotoGP 车队 / 厂商 —— team.name 通常含赞助商("Ducati Lenovo Team"),关键字匹配
    private static func motoGPTeam(_ n: String) -> String? {
        // 厂商优先(constructor.name 短串"Ducati"等)
        if n == "ducati"                { return "杜卡迪" }
        if n == "yamaha"                { return "雅马哈" }
        if n == "honda"                 { return "本田" }
        if n == "aprilia"               { return "阿普利亚" }
        if n == "ktm"                   { return "KTM" }
        // 车队(含赞助商前缀)
        if n.contains("ducati lenovo")  { return "杜卡迪联想厂队" }
        if n.contains("repsol honda")   { return "雷普索尔本田" }
        if n.contains("monster") && n.contains("yamaha") { return "魔爪雅马哈" }
        if n.contains("red bull") && n.contains("ktm") { return "红牛 KTM 厂队" }
        if n.contains("aprilia racing") { return "阿普利亚厂队" }
        if n.contains("vr46")           { return "VR46 车队" }
        if n.contains("gresini")        { return "格雷西尼" }
        if n.contains("trackhouse")     { return "Trackhouse" }
        if n.contains("lcr")            { return "LCR 本田" }
        if n.contains("tech3")          { return "Tech3 KTM" }
        if n.contains("pertamina") && n.contains("vr46") { return "Pertamina VR46" }
        if n.contains("pramac")         { return "Pramac" }
        // 厂商关键字兜底(车队名含厂商关键字时,前面赞助商前缀分支没命中才到这)
        if n.contains("ducati")         { return "杜卡迪" }
        if n.contains("yamaha")         { return "雅马哈" }
        if n.contains("honda")          { return "本田" }
        if n.contains("aprilia")        { return "阿普利亚" }
        if n.contains("ktm")            { return "KTM" }
        return nil
    }

    // WSSP / WSBK 车手 —— rider.fullName 大写"JAUME MASIA",已 lowercase。中文媒体覆盖少,
    // 译名按 CCTV5 + 虎扑赛车区主流用法,部分新生代未完全收敛保持谨慎。
    private static func wsspRiderShort(_ n: String) -> String? {
        if n.contains("zhang") || n.contains("张雪")  { return "张雪" }
        // WSBK 主组当代明星
        if n.contains("razgatlioglu")   { return "拉兹加特利奥卢" }
        if n.contains("bautista")       { return "鲍蒂斯塔" }
        if n.contains("iannone")        { return "扬诺内" }
        if n.contains("jonathan rea") || n == "rea" { return "雷亚" }
        if n.contains("sam lowes") || n.contains("samuel lowes") { return "萨姆·劳斯" }
        if n.contains("alex lowes") || n.contains("alexander lowes") { return "亚历克斯·劳斯" }
        if n.contains("rinaldi")        { return "里纳尔迪" }
        if n.contains("bassani")        { return "巴萨尼" }
        if n.contains("gerloff")        { return "格洛夫" }
        if n.contains("lecuona")        { return "莱库纳" }
        if n.contains("vierge")         { return "维尔赫" }
        if n.contains("gardner")        { return "加德纳" }
        if n.contains("petrucci")       { return "彼得鲁奇" }
        if n.contains("redding")        { return "雷丁" }
        if n.contains("loris baz") || n == "baz" { return "巴斯" }
        if n.contains("mackenzie")      { return "麦肯齐" }
        if n.contains("oettl") || n.contains("öttl") { return "厄特尔" }
        // WSSP 600 车手
        if n.contains("masia")          { return "马西亚" }
        if n.contains("manzi")          { return "曼齐" }
        if n.contains("huertas")        { return "韦尔塔斯" }
        if n.contains("mahias")         { return "马伊亚斯" }
        if n.contains("bulega")         { return "布莱加" }
        if n.contains("yamanaka")       { return "山中琉圣" }
        if n.contains("montella")       { return "蒙泰拉" }
        if n.contains("schroetter") || n.contains("schrötter") || n.contains("schrotter") { return "施罗特" }
        if n.contains("aegerter")       { return "阿格特" }
        if n.contains("locatelli")      { return "洛卡泰利" }
        if n.contains("oncu") || n.contains("öncü") { return "翁居" }
        if n.contains("debise")         { return "德比斯" }
        if n.contains("caricasulo")     { return "卡里卡苏洛" }
        if n.contains("vinales")        { return "维纳莱斯" }
        if n.contains("bendsneyder")    { return "本德斯奈德" }
        if n.contains("booth-amos") || n.contains("booth amos") { return "布斯-阿莫斯" }
        if n.contains("tuuli")          { return "图利" }
        if n.contains("van straalen") || n.contains("straalen") { return "范斯特拉伦" }
        if n.contains("navarro")        { return "纳瓦罗" }
        if n.contains("sofuoglu") || n.contains("sofuoğlu") { return "索富奥卢" }
        if n.contains("farioli")        { return "法廖利" }
        if n.contains("pratama") || n.contains("hendra")    { return "普拉塔马" }
        if n.contains("dalla porta") || n.contains("dalla_porta") { return "达拉·波尔塔" }
        if n.contains("marc garcia") || n.contains("marc garcía") { return "加西亚" }
        if n.contains("kofler")         { return "科夫勒" }
        if n.contains("ottaviani")      { return "奥塔维亚尼" }
        if n.contains("casadei")        { return "卡萨代" }
        return nil
    }

    private static func wsspRiderFull(_ n: String) -> String? {
        if n.contains("zhang") || n.contains("张雪")  { return "张雪" }
        // WSBK 主组
        if n.contains("razgatlioglu")   { return "托普拉克·拉兹加特利奥卢" }
        if n.contains("bautista")       { return "阿尔瓦罗·鲍蒂斯塔" }
        if n.contains("iannone")        { return "安德烈·扬诺内" }
        if n.contains("jonathan rea") || n == "rea" { return "乔纳森·雷亚" }
        if n.contains("sam lowes") || n.contains("samuel lowes") { return "萨姆·劳斯" }
        if n.contains("alex lowes") || n.contains("alexander lowes") { return "亚历克斯·劳斯" }
        if n.contains("rinaldi")        { return "迈克尔·里纳尔迪" }
        if n.contains("bassani")        { return "阿克塞尔·巴萨尼" }
        if n.contains("gerloff")        { return "加雷特·格洛夫" }
        if n.contains("lecuona")        { return "伊克·莱库纳" }
        if n.contains("vierge")         { return "哈维·维尔赫" }
        if n.contains("gardner")        { return "雷米·加德纳" }
        if n.contains("petrucci")       { return "达尼洛·彼得鲁奇" }
        if n.contains("redding")        { return "斯科特·雷丁" }
        if n.contains("loris baz") || n == "baz" { return "洛里斯·巴斯" }
        if n.contains("mackenzie")      { return "塔兰·麦肯齐" }
        if n.contains("oettl") || n.contains("öttl") { return "菲利普·厄特尔" }
        // WSSP 600
        if n.contains("masia")          { return "豪梅·马西亚" }
        if n.contains("manzi")          { return "斯特凡诺·曼齐" }
        if n.contains("huertas")        { return "阿德里安·韦尔塔斯" }
        if n.contains("mahias")         { return "卢卡斯·马伊亚斯" }
        if n.contains("bulega")         { return "尼科洛·布莱加" }
        if n.contains("yamanaka")       { return "山中琉圣" }
        if n.contains("montella")       { return "亚里·蒙泰拉" }
        if n.contains("schroetter") || n.contains("schrötter") || n.contains("schrotter") { return "马塞尔·施罗特" }
        if n.contains("aegerter")       { return "多米尼克·阿格特" }
        if n.contains("locatelli")      { return "安德烈亚·洛卡泰利" }
        if n.contains("oncu") || n.contains("öncü") { return "詹·翁居" }
        if n.contains("debise")         { return "瓦伦丁·德比斯" }
        if n.contains("caricasulo")     { return "费德里科·卡里卡苏洛" }
        if n.contains("vinales")        { return "伊萨克·维纳莱斯" }
        if n.contains("bendsneyder")    { return "博·本德斯奈德" }
        if n.contains("booth-amos") || n.contains("booth amos") { return "汤姆·布斯-阿莫斯" }
        if n.contains("tuuli")          { return "尼基·图利" }
        if n.contains("van straalen") || n.contains("straalen") { return "格伦·范斯特拉伦" }
        if n.contains("navarro")        { return "豪尔赫·纳瓦罗" }
        if n.contains("sofuoglu") || n.contains("sofuoğlu") { return "巴哈廷·索富奥卢" }
        if n.contains("farioli")        { return "菲利波·法廖利" }
        if n.contains("pratama") || n.contains("hendra")    { return "加朗·亨德拉·普拉塔马" }
        if n.contains("dalla porta") || n.contains("dalla_porta") { return "洛伦佐·达拉·波尔塔" }
        if n.contains("marc garcia") || n.contains("marc garcía") { return "马克·加西亚" }
        if n.contains("kofler")         { return "马克西米利安·科夫勒" }
        if n.contains("ottaviani")      { return "卢卡·奥塔维亚尼" }
        if n.contains("casadei")        { return "马蒂亚·卡萨代" }
        return nil
    }

    // WSSP 厂商 —— builder.name 全大写"DUCATI"
    private static func wsspBuilder(_ n: String) -> String? {
        if n == "ducati"                { return "杜卡迪" }
        if n == "yamaha"                { return "雅马哈" }
        if n == "honda"                 { return "本田" }
        if n == "kawasaki"              { return "川崎" }
        if n.contains("mv agusta") || n.contains("mvagusta") { return "MV 阿古斯塔" }
        if n == "triumph"               { return "凯旋" }
        if n == "qjmotor"               { return "QJ 摩托" }
        if n == "zxmoto"                { return "ZXMOTO" }
        if n == "bimota"                { return "比莫塔" }
        return nil
    }

    // FE 车手 —— driver.fullName 是 firstName+lastName 拼的"Antonio Felix Da Costa"
    private static func feDriverShort(_ n: String) -> String? {
        if n.contains("da costa")       { return "达科斯塔" }
        if n.contains("vandoorne")      { return "范多恩" }
        if n.contains("vergne")         { return "维尔涅" }
        if n.contains("di grassi")      { return "迪格拉西" }
        if n.contains("buemi")          { return "布埃米" }
        if n.contains("cassidy")        { return "卡西迪" }
        if n.contains("evans")          { return "埃文斯" }
        if n.contains("dennis")         { return "丹尼斯" }
        if n.contains("wehrlein")       { return "韦尔莱因" }
        if n.contains("guenther") || n.contains("günther") { return "京特" }
        if n.contains("rowland")        { return "罗兰" }
        if n.contains("bird")           { return "伯德" }
        if n.contains("hughes")         { return "休斯" }
        if n.contains("frijns")         { return "弗里恩斯" }
        if n.contains("mortara")        { return "莫塔拉" }
        if n.contains("sette camara")   { return "塞特·卡马拉" }
        if n.contains("nato")           { return "纳托" }
        if n.contains("mueller") || n.contains("muller") { return "穆勒" }
        if n.contains("ticktum")        { return "蒂克坦" }
        if n.contains("daruvala")       { return "达鲁瓦拉" }
        if n.contains("hauger")         { return "豪格" }
        // S11 (2024-2025) 新人 / 替补
        if n.contains("barnard")        { return "巴纳德" }
        if n.contains("maloney")        { return "马洛尼" }
        if n.contains("beckmann")       { return "贝克曼" }
        if n.contains("nyck de vries") || n.contains("de vries") { return "德弗里斯" }
        if n.contains("drugovich")      { return "德鲁戈维奇" }
        if n.contains("collet")         { return "科莱特" }
        // 经典 FE 名将(已转 IndyCar / F1 / 退役)
        if n.contains("piquet")         { return "皮奎特" }
        if n.contains("rosenqvist")     { return "罗森奎斯特" }
        if n.contains("lotterer")       { return "洛特雷尔" }
        if n.contains("loic duval") || n.contains("loïc duval") { return "杜瓦尔" }
        if n.contains("turvey")         { return "特维" }
        if n.contains("d'ambrosio") || n.contains("dambrosio") { return "丹布罗西奥" }
        return nil
    }

    private static func feDriverFull(_ n: String) -> String? {
        if n.contains("da costa")       { return "安东尼奥·费利克斯·达科斯塔" }
        if n.contains("vandoorne")      { return "斯托弗·范多恩" }
        if n.contains("vergne")         { return "让-埃里克·维尔涅" }
        if n.contains("di grassi")      { return "卢卡斯·迪格拉西" }
        if n.contains("buemi")          { return "塞巴斯蒂安·布埃米" }
        if n.contains("cassidy")        { return "尼克·卡西迪" }
        if n.contains("evans")          { return "米奇·埃文斯" }
        if n.contains("dennis")         { return "杰克·丹尼斯" }
        if n.contains("wehrlein")       { return "帕斯卡·韦尔莱因" }
        if n.contains("guenther") || n.contains("günther") { return "马克斯·京特" }
        if n.contains("rowland")        { return "奥利弗·罗兰" }
        if n.contains("bird")           { return "萨姆·伯德" }
        if n.contains("hughes")         { return "杰克·休斯" }
        if n.contains("frijns")         { return "罗宾·弗里恩斯" }
        if n.contains("mortara")        { return "埃多阿尔多·莫塔拉" }
        if n.contains("sette camara")   { return "塞尔吉奥·塞特·卡马拉" }
        if n.contains("nato")           { return "诺曼·纳托" }
        if n.contains("mueller") || n.contains("muller") { return "尼科·穆勒" }
        if n.contains("ticktum")        { return "丹·蒂克坦" }
        if n.contains("daruvala")       { return "杰汉·达鲁瓦拉" }
        if n.contains("hauger")         { return "丹尼斯·豪格" }
        // S11 新人 / 替补
        if n.contains("barnard")        { return "泰勒·巴纳德" }
        if n.contains("maloney")        { return "赞·马洛尼" }
        if n.contains("beckmann")       { return "大卫·贝克曼" }
        if n.contains("nyck de vries") || n.contains("de vries") { return "尼克·德弗里斯" }
        if n.contains("drugovich")      { return "费利佩·德鲁戈维奇" }
        if n.contains("collet")         { return "凯欧·科莱特" }
        // 经典名将
        if n.contains("piquet")         { return "小尼尔森·皮奎特" }
        if n.contains("rosenqvist")     { return "费利克斯·罗森奎斯特" }
        if n.contains("lotterer")       { return "安德烈·洛特雷尔" }
        if n.contains("loic duval") || n.contains("loïc duval") { return "洛伊克·杜瓦尔" }
        if n.contains("turvey")         { return "奥利弗·特维" }
        if n.contains("d'ambrosio") || n.contains("dambrosio") { return "热罗姆·丹布罗西奥" }
        return nil
    }

    // FE 车队 —— team.name 大写"PORSCHE FORMULA E TEAM"
    private static func feTeam(_ n: String) -> String? {
        if n.contains("porsche")        { return "保时捷" }
        if n.contains("jaguar")         { return "捷豹" }
        if n.contains("nissan")         { return "日产" }
        if n.contains("andretti")       { return "安德雷蒂" }
        if n.contains("envision")       { return "远景" }
        if n.contains("mahindra")       { return "马恒达" }
        if n.contains("ds penske") || n.contains("ds-penske") { return "DS 彭斯克" }
        if n.contains("maserati")       { return "玛莎拉蒂" }
        if n.contains("abt") && n.contains("cupra") { return "ABT 库普拉" }
        if n.contains("mclaren")        { return "迈凯伦" }
        if n.contains("erebus")         { return "Erebus" }
        if n.contains("kiro")           { return "Kiro" }
        if n.contains("lola")           { return "Lola" }
        if n.contains("yamaha")         { return "雅马哈" }
        return nil
    }

    // MARK: - 英文模式赞助商清理

    /// FE / MotoGP 车队名常带赞助商前缀("Monster Energy Yamaha MotoGP")—— 英文模式下剥到识别度高的核心。
    private static func cleanupSponsors(_ raw: String) -> String {
        let pattern = #"^(?:Monster Energy |Repsol |Red Bull |Aprilia Racing |Pertamina Enduro |TAG Heuer |Tata |TCS |NEOM |Stake |Kick |MoneyGram |Visa Cash App )+"#
        let cleaned = raw.replacingOccurrences(
            of: pattern, with: "", options: [.regularExpression, .caseInsensitive]
        )
        return cleaned.isEmpty ? raw : cleaned
    }
}
