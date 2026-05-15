//
//  MotorsportNamesCompletenessTests.swift
//  PoleTests
//
//  Translation completeness audit for MotorsportNames.
//
//  目的: 不修 mapping, 只暴露缺失项 — 让 CI / 本地 test failure 列出
//  "你这个 raw 名没在 Localization.swift 里被翻译"。
//
//  注意:
//  - 所有 mapping 函数对英文模式直接返回原文 — 测试前先把 languageMode 强制为 zh,
//    否则所有 assert 都会"假阳性"通过(英文模式 translated == raw 是设计行为)。
//  - driver mapping 签名是 `driverShortName(rawFullName:series:)`, team 是 `teamName(raw:series:)`。
//  - MotorsportSeries 枚举 case 是 `.wssp` (不是 `.wsbk`),因为数据源是 WSSP class。
//

import Foundation
import Testing
import PoleDomain

@Suite("MotorsportNames translation completeness")
struct MotorsportNamesCompletenessTests {

    /// 把 languageMode 强制为 zh, 确保 mapping 函数不会因英文模式短路返回原文。
    /// 每个 @Test 入口先调一遍 (UserDefaults 是进程全局, set 一次足够但显式更稳)。
    private func forceZh() {
        UserDefaults.standard.set("zh", forKey: "languageMode")
    }

    // MARK: - F1

    @Test("F1 2024-2026 drivers have Chinese short names")
    func f1DriversShort() {
        forceZh()
        let knownDrivers = [
            // 现役 2024-2026
            "Verstappen", "Norris", "Leclerc", "Sainz", "Hamilton", "Russell",
            "Piastri", "Alonso", "Stroll", "Tsunoda", "Bearman", "Ocon",
            "Gasly", "Hülkenberg", "Albon", "Bortoleto", "Antonelli",
            "Lawson", "Hadjar", "Doohan", "Colapinto",
        ]
        var missing: [String] = []
        for d in knownDrivers {
            let translated = MotorsportNames.driverShortName(rawFullName: d, series: .f1)
            if translated == d {
                missing.append(d)
            }
        }
        #expect(missing.isEmpty, "F1 drivers missing Chinese short name: \(missing.joined(separator: ", "))")
    }

    @Test("F1 2024-2026 drivers have Chinese full names")
    func f1DriversFull() {
        forceZh()
        let knownDrivers = [
            "Max Verstappen", "Lando Norris", "Charles Leclerc", "Carlos Sainz",
            "Lewis Hamilton", "George Russell", "Oscar Piastri", "Fernando Alonso",
            "Lance Stroll", "Yuki Tsunoda", "Oliver Bearman", "Esteban Ocon",
            "Pierre Gasly", "Nico Hülkenberg", "Alexander Albon", "Gabriel Bortoleto",
            "Kimi Antonelli", "Liam Lawson", "Isack Hadjar", "Jack Doohan",
            "Franco Colapinto",
        ]
        var missing: [String] = []
        for d in knownDrivers {
            let translated = MotorsportNames.driverFullName(rawFullName: d, series: .f1)
            if translated == d {
                missing.append(d)
            }
        }
        #expect(missing.isEmpty, "F1 drivers missing Chinese full name: \(missing.joined(separator: ", "))")
    }

    @Test("F1 teams have Chinese names")
    func f1Teams() {
        forceZh()
        let knownTeams = [
            "Red Bull", "Mercedes", "Ferrari", "McLaren", "Aston Martin",
            "Alpine", "Williams", "RB", "Haas", "Kick Sauber",
        ]
        var missing: [String] = []
        for t in knownTeams {
            let translated = MotorsportNames.teamName(raw: t, series: .f1)
            if translated == t {
                missing.append(t)
            }
        }
        #expect(missing.isEmpty, "F1 teams missing Chinese: \(missing.joined(separator: ", "))")
    }

    // MARK: - MotoGP

    @Test("MotoGP 2024-2026 riders have Chinese short names")
    func motoGPRidersShort() {
        forceZh()
        let knownRiders = [
            "Francesco Bagnaia", "Jorge Martin", "Marc Marquez", "Alex Marquez",
            "Pedro Acosta", "Marco Bezzecchi", "Maverick Vinales", "Fabio Quartararo",
            "Aleix Espargaro", "Joan Mir", "Franco Morbidelli", "Fabio Di Giannantonio",
            "Brad Binder", "Miguel Oliveira", "Enea Bastianini", "Raul Fernandez",
            "Augusto Fernandez", "Jack Miller", "Johann Zarco", "Luca Marini",
            "Alex Rins", "Takaaki Nakagami",
        ]
        var missing: [String] = []
        for r in knownRiders {
            let translated = MotorsportNames.driverShortName(rawFullName: r, series: .motogp)
            if translated == r {
                missing.append(r)
            }
        }
        #expect(missing.isEmpty, "MotoGP riders missing Chinese short name: \(missing.joined(separator: ", "))")
    }

    @Test("MotoGP 2024-2026 riders have Chinese full names")
    func motoGPRidersFull() {
        forceZh()
        let knownRiders = [
            "Francesco Bagnaia", "Jorge Martin", "Marc Marquez", "Alex Marquez",
            "Pedro Acosta", "Marco Bezzecchi", "Maverick Vinales", "Fabio Quartararo",
            "Aleix Espargaro", "Joan Mir", "Franco Morbidelli", "Fabio Di Giannantonio",
            "Brad Binder", "Miguel Oliveira", "Enea Bastianini", "Raul Fernandez",
            "Augusto Fernandez", "Jack Miller", "Johann Zarco", "Luca Marini",
            "Alex Rins", "Takaaki Nakagami",
        ]
        var missing: [String] = []
        for r in knownRiders {
            let translated = MotorsportNames.driverFullName(rawFullName: r, series: .motogp)
            if translated == r {
                missing.append(r)
            }
        }
        #expect(missing.isEmpty, "MotoGP riders missing Chinese full name: \(missing.joined(separator: ", "))")
    }

    @Test("MotoGP teams have Chinese names")
    func motoGPTeams() {
        forceZh()
        let knownTeams = [
            "Ducati Lenovo Team", "Pramac Racing", "Aprilia Racing",
            "Red Bull KTM Factory Racing", "Repsol Honda Team",
            "Monster Energy Yamaha MotoGP", "Tech3 KTM Factory Racing",
            "Pertamina Enduro VR46 Racing Team", "Gresini Racing MotoGP",
            "LCR Honda",
        ]
        var missing: [String] = []
        for t in knownTeams {
            let translated = MotorsportNames.teamName(raw: t, series: .motogp)
            if translated == t {
                missing.append(t)
            }
        }
        #expect(missing.isEmpty, "MotoGP teams missing Chinese: \(missing.joined(separator: ", "))")
    }

    // MARK: - WSSP (WorldSBK class)

    @Test("WSSP / WSBK 2024-2026 riders have Chinese short names")
    func wsspRidersShort() {
        forceZh()
        let knownRiders = [
            "Stefano Manzi", "Nicolò Bulega", "Dominique Aegerter",
            "Federico Caricasulo", "Adrian Huertas", "Niki Tuuli",
            "Bahattin Sofuoğlu", "Marcel Schrötter", "Andrea Locatelli",
            "Can Öncü", "Jaume Masia", "Yari Montella",
        ]
        var missing: [String] = []
        for r in knownRiders {
            let translated = MotorsportNames.driverShortName(rawFullName: r, series: .wssp)
            if translated == r {
                missing.append(r)
            }
        }
        #expect(missing.isEmpty, "WSSP riders missing Chinese short name: \(missing.joined(separator: ", "))")
    }

    @Test("WSSP / WSBK 2024-2026 riders have Chinese full names")
    func wsspRidersFull() {
        forceZh()
        let knownRiders = [
            "Stefano Manzi", "Nicolò Bulega", "Dominique Aegerter",
            "Federico Caricasulo", "Adrian Huertas", "Niki Tuuli",
            "Bahattin Sofuoğlu", "Marcel Schrötter", "Andrea Locatelli",
            "Can Öncü", "Jaume Masia", "Yari Montella",
        ]
        var missing: [String] = []
        for r in knownRiders {
            let translated = MotorsportNames.driverFullName(rawFullName: r, series: .wssp)
            if translated == r {
                missing.append(r)
            }
        }
        #expect(missing.isEmpty, "WSSP riders missing Chinese full name: \(missing.joined(separator: ", "))")
    }

    @Test("WSSP builders have Chinese names")
    func wsspBuilders() {
        forceZh()
        // builder.name 通常全大写 — mapping 内部 normalize 走 lowercased.
        let knownBuilders = [
            "Ducati", "Yamaha", "Honda", "Kawasaki", "MV Agusta", "Triumph",
        ]
        var missing: [String] = []
        for b in knownBuilders {
            let translated = MotorsportNames.teamName(raw: b, series: .wssp)
            if translated == b {
                missing.append(b)
            }
        }
        #expect(missing.isEmpty, "WSSP builders missing Chinese: \(missing.joined(separator: ", "))")
    }

    // MARK: - Formula E

    @Test("Formula E 2024-2026 drivers have Chinese short names")
    func feDriversShort() {
        forceZh()
        let knownDrivers = [
            "Pascal Wehrlein", "Jake Dennis", "Antonio Felix Da Costa",
            "Nick Cassidy", "Jean-Eric Vergne", "Stoffel Vandoorne",
            "Sam Bird", "Robin Frijns", "Edoardo Mortara",
            "Oliver Rowland", "Mitch Evans", "Nico Mueller",
            "Sebastien Buemi", "Dan Ticktum", "Sergio Sette Camara",
            "Jake Hughes",
        ]
        var missing: [String] = []
        for d in knownDrivers {
            let translated = MotorsportNames.driverShortName(rawFullName: d, series: .fe)
            if translated == d {
                missing.append(d)
            }
        }
        #expect(missing.isEmpty, "FE drivers missing Chinese short name: \(missing.joined(separator: ", "))")
    }

    @Test("Formula E 2024-2026 drivers have Chinese full names")
    func feDriversFull() {
        forceZh()
        let knownDrivers = [
            "Pascal Wehrlein", "Jake Dennis", "Antonio Felix Da Costa",
            "Nick Cassidy", "Jean-Eric Vergne", "Stoffel Vandoorne",
            "Sam Bird", "Robin Frijns", "Edoardo Mortara",
            "Oliver Rowland", "Mitch Evans", "Nico Mueller",
            "Sebastien Buemi", "Dan Ticktum", "Sergio Sette Camara",
            "Jake Hughes",
        ]
        var missing: [String] = []
        for d in knownDrivers {
            let translated = MotorsportNames.driverFullName(rawFullName: d, series: .fe)
            if translated == d {
                missing.append(d)
            }
        }
        #expect(missing.isEmpty, "FE drivers missing Chinese full name: \(missing.joined(separator: ", "))")
    }

    @Test("Formula E teams have Chinese names")
    func feTeams() {
        forceZh()
        let knownTeams = [
            "Porsche", "Jaguar", "Nissan", "Mahindra", "Andretti",
            "DS Penske", "Maserati", "Envision", "McLaren",
        ]
        var missing: [String] = []
        for t in knownTeams {
            let translated = MotorsportNames.teamName(raw: t, series: .fe)
            if translated == t {
                missing.append(t)
            }
        }
        #expect(missing.isEmpty, "FE teams missing Chinese: \(missing.joined(separator: ", "))")
    }
}
