# Sparkle Appcast 版本语义与发版脚本设计

**日期:** 2026-07-16  
**状态:** 已确认  
**路径:** 路径 2（appcast 脚本 + 现网修正 + 发版清单）

## 概述

修正 QuotaBar Sparkle 更新源中 `sparkle:version` 与本机 `CFBundleVersion`（build）比较错误的问题，使旧版（如营销 2.0.3 / build 4）能正确发现新版（营销 2.0.4 / build 5），走 Sparkle **标准更新窗口**（下载进度 → 安装提示）。通过小型脚本生成/修正 appcast 条目，并完善发版文档中的边界情况，避免再次把营销版本号写入 `sparkle:version`。

## 背景与根因

已验证本机 `/Applications/QuotaBar.app`：

- `CFBundleShortVersionString` = `2.0.3`
- `CFBundleVersion` = `4`

`gh-pages` 上 2.0.4 条目为：

```xml
sparkle:version="2.0.4"  <!-- 误用营销号 -->
length="1407629"
```

Sparkle 用 `CFBundleVersion` 与 `sparkle:version` 做机器比较。比较 `4` 与 `2.0.4` 时，首位 `4 > 2`，判定本机「更新」，于是弹出 *You're up to date*，同时文案仍显示营销号 2.0.3 / 2.0.4，造成矛盾体验。

正确语义（Sparkle 官方约定）：

| 字段 | 含义 | 示例（v2.0.4） |
|------|------|----------------|
| `CFBundleVersion` / `sparkle:version` | 单调递增的机器 build | `5` |
| `CFBundleShortVersionString` / `sparkle:shortVersionString` | 给人看的营销版本 | `2.0.4` |

项目源码：`project.yml` 中 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；`Info.plist` 已用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`。

## 目标

1. 现网修正 2.0.4 appcast：`sparkle:version="5"`，并增加 `sparkle:shortVersionString="2.0.4"`；`length` 保持与已上传 DMG 一致（1407629）。
2. 新增 `scripts/update-appcast.sh`：用营销版本 + build + 本地 DMG 插入或修正条目，自动计算 `length`。
3. 更新 `docs/release-process.md` 与 `docs/sparkle-integration.md`：字段表、脚本用法、边界与检查清单。
4. 保持 Sparkle 标准更新 UI；菜单仅沿用现有 `UpdateService` 状态文案（不自定义进度条）。

## 非目标

- 自定义 `SPUUserDriver` / 菜单内嵌进度条
- Sparkle 官方 `generate_appcast` 流水线
- 一键串联 bump → 打包 → upload → push gh-pages
- 强制为 enclosure 增加 EdDSA `sparkle:edSignature`（可在文档中列为后续可选）

## 架构

```
发版者
  ├─ package-dmg.sh          → dist/QuotaBar-X.Y.Z.dmg
  ├─ update-appcast.sh       → 写入/修正 appcast.xml（length + version 语义）
  └─（人工确认后）push gh-pages

运行中的旧版 App
  └─ UpdateService / SPUStandardUpdaterController
       └─ SUFeedURL → appcast.xml
            └─ 发现 build 更新 → Sparkle 标准窗（进度 + 安装）
```

| 单元 | 职责 |
|------|------|
| `scripts/update-appcast.sh` | 校验参数与 DMG；计算 length；插入新 item 或按规则替换错误 enclosure version；校验 build 单调性（在可解析时） |
| `appcast.xml`（gh-pages） | 更新源；新条目必须使用整数 build + shortVersionString |
| 发版文档 | 唯一操作说明与边界表 |
| `UpdateService` | **不改行为**（除非文档示例与 i18n 需极小对齐；默认零代码变更） |

## 脚本契约

### 命令形态

```bash
./scripts/update-appcast.sh \
  --marketing 2.0.4 \
  --build 5 \
  --dmg dist/QuotaBar-2.0.4.dmg \
  --appcast /path/to/appcast.xml \
  [--url URL] \
  [--date "RFC2822"] \
  [--title "Version 2.0.4"] \
  [--replace-enclosure-version 2.0.4]
```

| 参数 | 必填 | 说明 |
|------|------|------|
| `--marketing` | 是 | 营销版本 → `sparkle:shortVersionString` 与默认 title |
| `--build` | 是 | 正整数 → `sparkle:version` |
| `--dmg` | 是 | 本地 DMG；必须存在且 size > 0 |
| `--appcast` | 是 | 目标 XML 路径（调用方显式传入；例如 gh-pages worktree 中的 `appcast.xml`） |
| `--url` | 否 | 默认 `https://github.com/nmsn/quota-bar/releases/download/v{marketing}/QuotaBar-{marketing}.dmg` |
| `--date` | 否 | 默认当前时间的 RFC2822（+0800 或本地） |
| `--title` | 否 | 默认 `Version {marketing}` |
| `--replace-enclosure-version OLD` | 否 | 将已有 item 中 `sparkle:version="OLD"`（且同 marketing 标题或同 URL）的 enclosure 改为新 build，并写入/更新 `shortVersionString` 与 `length` |

### 行为规则

1. **新建条目（无 `--replace-enclosure-version`）**  
   - 若已存在 `sparkle:version="{build}"`（整数匹配）→ 非 0 退出。  
   - 解析 channel 内各 enclosure 的 `sparkle:version`：凡**纯整数**者取最大值；若 `build <= max` → 非 0 退出（禁止回退）。  
   - 值为营销形态（含 `.` 的多段）的旧条目：**不参与**整数 max 比较，向 stderr 打印一次迁移警告。  
   - 在 `<channel>` 内、第一条 `<item>` **之前**插入新 item。

2. **修正条目（带 `--replace-enclosure-version OLD`）**  
   - 找到 `sparkle:version="OLD"` 的 enclosure（优先匹配默认/传入 URL 或 title 含 marketing）。  
   - 改写为 `sparkle:version="{build}"`，设置 `sparkle:shortVersionString="{marketing}"`，`length` 重算自 `--dmg`。  
   - 找不到匹配 → 非 0 退出。  
   - 用于一次性修正现网错误的 `version="2.0.4"`。

3. **历史条目**  
   - 默认**不改写**其他历史 item 的旧营销式 `sparkle:version`。  
   - 已安装 build 4 的用户依赖修正后的 2.0.4 条目（version=5）完成升级。

4. **输出**  
   - 成功时打印将写入的 version / shortVersionString / length / url。  
   - 不自动 `git commit` / `git push`（遵守仓库 HITL）。

### 新条目 XML 形状

```xml
<item>
  <title>Version 2.0.4</title>
  <pubDate>Thu, 16 Jul 2026 10:58:00 +0800</pubDate>
  <enclosure url="https://github.com/nmsn/quota-bar/releases/download/v2.0.4/QuotaBar-2.0.4.dmg"
             sparkle:version="5"
             sparkle:shortVersionString="2.0.4"
             length="1407629"
             type="application/octet-stream"/>
</item>
```

## 现网一次性修正

在 gh-pages worktree 中对当前 `appcast.xml` 执行等价于：

```bash
./scripts/update-appcast.sh \
  --marketing 2.0.4 \
  --build 5 \
  --dmg dist/QuotaBar-2.0.4.dmg \
  --appcast ./appcast.xml \
  --replace-enclosure-version 2.0.4
```

然后经用户确认后 commit / push `gh-pages`。  
`length` 必须以本地与 Release 上已发布的 `QuotaBar-2.0.4.dmg` 为准（已知 1407629）；若本地无文件，可从 Release 下载到临时路径再跑脚本。

## 边界情况

| 场景 | 预期行为 |
|------|----------|
| 本机 build 4，appcast 最新 build 5 | 发现更新 → Sparkle 标准下载/安装窗 |
| 本机已是 build 5 | You’re up to date |
| GitHub Pages CDN 未刷新 | 仍可能读到旧 XML；文档要求用 raw.githubusercontent.com 自检，或等待 Pages |
| DMG 缺失或 size=0 | 脚本失败，不改 XML |
| 上传后又替换了同名 DMG 未改 length | Sparkle 可能失败；清单要求：改 DMG 必须重跑脚本并更新 appcast |
| `project.yml` 与包内 Info 不一致 | 清单要求打包后核对 ShortVersion/Version；本设计不实现 `--verify-app` |
| 历史 item 仍为 `version=2.0.x` 营销号 | 保留；新比较只依赖正确的整数 build 条目 |
| 无 edSignature | 维持现状；与现网一致 |
| 菜单进度条 | 不做；标准窗负责进度与安装 |

## 文档变更

### `docs/sparkle-integration.md`

- 明确 version vs shortVersionString 表  
- 替换错误示例（勿再写 `sparkle:version="2.0.2"` 作为营销号）  
- 增加 `update-appcast.sh` 用法与现网修正示例  
- 边界：CDN、length、build 单调

### `docs/release-process.md`

- 在「创建 Release / 上传 DMG」之后增加「更新 appcast」步骤，强制：  
  1. `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION` 已合入 main 且与包内一致  
  2. 跑 `update-appcast.sh`  
  3. 确认后 push gh-pages  
- Checklist 增加：build 为整数、shortVersionString 已设、length 已核对、raw appcast 已含新条目

### `CLAUDE.md`（可选一小段）

- 指向脚本与「禁止把营销号写入 sparkle:version」

## 测试与验收

**脚本（可用 fixture XML + 临时小文件冒充 DMG）：**

1. 插入：build 递增成功；length 正确  
2. 插入：build ≤ 已有最大整数 build → 失败  
3. 插入：已存在相同整数 version → 失败  
4. replace：将 `version="2.0.4"` 改为 `5` 并写入 shortVersionString  
5. replace：找不到 OLD → 失败  
6. DMG 不存在 → 失败  

**人工验收：**

1. 安装仍为 2.0.3 / build 4 的机器，检查更新 → **出现更新 UI**（非 up to date）  
2. 可走完下载进度并提示安装（标准窗）  
3. 升到 build 5 后再检查 → 已是最新  
4. `curl` raw gh-pages appcast：2.0.4 enclosure 为 `sparkle:version="5"` 且含 `shortVersionString="2.0.4"`

## 风险与迁移说明

- 仅修正最新错误条目即可覆盖「从 2.0.3(build4) → 2.0.4(build5)」主路径。  
- 更早、仅有营销式 version 的条目不参与可靠比较；用户需先到任一「正确整数 build」条目之后，后续更新才完全按 build 链工作。  
- Pages 缓存可能导致修正后短暂仍读旧 XML。

## 验收标准

1. 脚本按契约实现并通过上述脚本测试。  
2. gh-pages appcast 中 2.0.4 条目 version=5、shortVersionString=2.0.4、length 正确。  
3. 文档不再示范营销号作为 `sparkle:version`。  
4. 真机：2.0.3(build4) 能看到可下载/安装的更新流程。
