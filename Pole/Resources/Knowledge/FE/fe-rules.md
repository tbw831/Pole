---
series: fe
topic: rules
---

# Formula E 赛事简介

Formula E = FIA 全电动方程式锦标赛,2014 创立。第一届开普勒街道为揭幕站。
车型 Gen3(2023+ 用)输出 350 kW(峰值 470 hp),3 秒破百,顶速 ~322 km/h。
特点:**单日赛**(不像 F1/MotoGP 三天周末)。
赛事日 = 一日内跑 FP / 排位 / 正赛全部完成,周六或周日单日完成。
Formula E 比赛地大多数是城市街道 — Berlin / Tokyo / Roma / Sao Paulo / Diriyah / NYC 等。

# Formula E 周末赛制

单日赛流程:
- FP1(早上)
- FP2(中午前)
- Qual Group A / B(中午,把车手分两组淘汰跑;每组前 4 进 Knockout)
- Knockout 1/4 决赛 → 半决赛 → 决赛(决出 Pole + 前 8 grid)
- Race(下午,~45 分钟 + 1 圈)

# Formula E 积分制度

正赛前 10 名:25/18/15/12/10/8/6/4/2/1(同 F1 一致)。
**Pole Position +3 分**(Knockout 决赛胜者)。
**Fastest Lap +1 分**(必须前 10 完赛才算)。
所以一站车手最多得 25 + 3 + 1 = **29 分**。
车队榜按车手分相加。

# Formula E Attack Mode

每场比赛车手必须激活 Attack Mode 至少 2 次。
进入方式:行驶过指定 Activation Zone(赛道偏离主线一小段),触发后:
- 输出从 300 kW 提升到 350 kW(+ ~67 hp)
- 持续时间由当场比赛决定,通常 4-8 分钟
- 必须在剩余时间用完 — 没用完不计入比赛
策略组件:车队决定何时激活 — 有人受其他车攻击时再开,有人主动超车前先开。

# Formula E Energy Management

电量管理 = FE 核心策略。每场起步带 100% 电,跑 ~45 分钟 + 1 圈。
车手必须实时调整再生(再充电下坡 / 重刹)和释放比例,
后段如果还有大于 28% 电就被罚(显示控制不准)。
赛中信号灯提示"目标 SOC"(剩余电量),低于该值的车手要尽量节能。
最后几圈 "battery push" 时段大家都开 Attack Mode + 全释放,顶速最高。

# Formula E 进站与轮胎

通常**无强制进站**(电池一充到底,无补能)。
轮胎:Hankook 全天候胎(干雨通用),除非雨极大才换专用雨胎。
没有 F1 那种轮胎策略 — FE 策略全在能量管理。
