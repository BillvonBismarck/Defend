# 给 Maker Agent 的指令：在项目内落地 defense 脱耦

> 用法：把下面代码块里的内容整段粘贴到「Emoji幸存」Maker 项目的 AI 对话里。指令是自足的：能联网就照仓库分支做，不能联网也可以在项目内构造（源文件都在项目里）。执行完把结果发我，我可以远程核对。

```text
任务：把 defense 包与 legacy 模块解耦。只做结构解耦，不改玩法数值、不改规则逻辑。

背景与目标
- defense/LegacyFX.lua 依赖 fx.Particle / fx.GameAudio / ui.DamageNumber / fx.ScreenShake；defense/Runtime.lua 依赖 ui.DamageNumber。
- 目标：defense 包只依赖 defense.*、defense.fx.* 与平台库（urhox-libs/*、cjson）。
- 已有参考实现：Gitee 仓库 Ecnahc1014/emoji-survivors 的分支 defense-standalone 下 standalone/scripts/defense/（含 FX.lua 与 fx/ 下 7 个文件）。
  若你能访问网络，请直接按该分支的文件内容新建；若不能，按下面的等价步骤在本项目内构造（源文件都在本项目里）。

一、新建 8 个文件（只改 require，其余内容原样复制）
1) scripts/defense/fx/Audio.lua        ← 原文复制 scripts/fx/GameAudio.lua
2) scripts/defense/fx/Shake.lua        ← 原文复制 scripts/fx/ScreenShake.lua
3) scripts/defense/fx/DamageNumber.lua ← 原文复制 scripts/ui/DamageNumber.lua
4) scripts/defense/fx/Glow.lua         ← 原文复制 scripts/fx/Glow.lua
5) scripts/defense/fx/PerfQuality.lua  ← 原文复制 scripts/utils/PerfQuality.lua
6) scripts/defense/fx/Particle.lua     ← 复制 scripts/fx/Particle.lua，并把三处 require 改成：
     require("fx.Glow")         → require("defense.fx.Glow")
     require("utils.FPSMonitor") → require("defense.fx.FPSMonitor")
     require("utils.PerfQuality")→ require("defense.fx.PerfQuality")
7) scripts/defense/fx/FPSMonitor.lua   ← 复制 scripts/utils/FPSMonitor.lua，并做三处改动：
     a. require("fx.Glow") → require("defense.fx.Glow")
     b. 在 `local FPSMonitor = {}` 之后新增一行：FPSMonitor.fontId = -1
     c. 在 Render() 里删除 `local HUD = require("ui.HUD")`，并把紧随的取字体那行改为：
          local zpix = (FPSMonitor.fontId and FPSMonitor.fontId >= 0) and FPSMonitor.fontId or font
8) scripts/defense/FX.lua ← 复制 scripts/defense/LegacyFX.lua，并把四行 require 改成：
     require("fx.Particle")      → require("defense.fx.Particle")
     require("fx.GameAudio")     → require("defense.fx.Audio")
     require("ui.DamageNumber")  → require("defense.fx.DamageNumber")
     require("fx.ScreenShake")   → require("defense.fx.Shake")
   注意：变量名保持原样（例如仍写 local LegacyFX = require("defense.FX")），只改 require 的字符串。

二、改 5 个文件的引用（只改 require 与测试桩名，不动逻辑）
1) scripts/defense/Runtime.lua
   - require("defense.LegacyFX") → require("defense.FX")（变量名不变）
   - require("ui.DamageNumber")  → require("defense.fx.DamageNumber")
2) scripts/defense/Board.lua：require("defense.LegacyFX") → require("defense.FX")
3) scripts/defense/View.lua：require("defense.LegacyFX") → require("defense.FX")
4) scripts/defense/EmergenceTests.lua
   - require("defense.LegacyFX") → require("defense.FX")
   - 桩表键名（模块名列表与 package.loaded[...] 两处都要改）：
       "fx.Particle"      → "defense.fx.Particle"
       "fx.GameAudio"     → "defense.fx.Audio"
       "ui.DamageNumber"  → "defense.fx.DamageNumber"
       "fx.ScreenShake"   → "defense.fx.Shake"
5) scripts/defense/CompletionTests.lua：与上一条同样的四处桩名替换

三、验收要求
1. 不要删除 scripts/defense/LegacyFX.lua（保留作回滚保险，确认无误后再删）。
2. 全仓检索确认 defense/ 目录下不再出现：require("fx.、require("ui.、require("utils.、require("defense.LegacyFX")。
3. 运行 defense 自带回归（Tests 模块的 Run 入口，例如 Tests.Run()），报告 passed / failed / not_run 三个数；
   本地参考基线：passed=80、failed=0、not_run=8（未跑的 8 例都是 UIART_*，只因缺少平台库 urhox-libs/UI/Core/Theme）。
4. 若有失败：先按失败项回退该处改动并报告，不要顺手修改玩法逻辑或数值。
5. 完成后回报：新建文件清单、修改文件清单、检索结果、测试三项数字。
```

## 落地的后续（你做完上面的步骤之后）

1. 把测试结果发我，我可以远程读取项目文件做核对（接口：`scripts/list`、`scripts/content`），必要时重跑本地回归；
2. 确认无误后再删 `defense/LegacyFX.lua`，并逐步移除 `battle/`、`meta/`、`ui/`、`fx/`、`social/`、`Achievement.lua`、`SaveData.lua` 等 legacy 文件；
3. 之后把 v0.2/v0.3 文档与代码对齐：把 `Q05`、`Q16–Q21` 等「临时决策」逐条确认或改写。
