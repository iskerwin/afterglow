# 霞光 Afterglow

预测当地 **朝霞 / 晚霞 / 火烧云** 的 iOS App，给摄影爱好者用。

- **霞光指数 0–100**：分为 无霞 / 微霞 / 小烧 / 中烧 / 大烧，并解释「为什么是这个分数」
- **霞光地图**：以你为中心约 200 km 范围的热力网格，标出周边最佳机位，一键导航；虚线指示太阳方向
- **未来 7 天** 每天的朝霞、晚霞预测；**黄金时刻 / 最佳霞光 / 蓝调时刻** 时间窗
- **历史档案**：自动记录每天的预测与实况回算值，近 30 天柱状图；支持实拍打卡（照片 + 星级），统计预测吻合度
- 收藏机位、高指数事件提前 1 小时通知
- 数据来自 [Open-Meteo](https://open-meteo.com/)（免费、无需 API Key）

## 预测原理

火烧云 = **画布** × **光路** × **视线** × **大气** × **降水**

| 因子 | 说明 |
| --- | --- |
| 画布 | 本地高云 + 中云合成覆盖率，40%–80% 最佳。太晴没有可染色的云，太厚透不过光 |
| 光路 | 日落后阳光贴着地平线从太阳方向照来。沿 **太阳方位角** 采样 30 / 70 / 115 km 处的低云（及厚中云），越少光越能照到头顶的云底 —— 这是判断火烧云最关键的一步 |
| 视线 | 本地低云过多会遮住天空 |
| 大气 | 能见度、相对湿度、气溶胶光学厚度 AOD（0.1–0.35 颜色最浓） |
| 降水 | 正在下雨扣分，雨后 1–3 小时放晴加分 |

评分时刻取日落后 10 分钟 / 日出前 10 分钟。太阳位置、日出日落、黄金/蓝调时刻均在本地计算。

## 构建 IPA

仓库自带 GitHub Actions（`.github/workflows/build-ipa.yml`）：每次推送到 `main` 都会在 macOS 上用 XcodeGen 生成工程并构建**未签名 IPA**，发布到 Releases 的 `latest`；打 `v*` 标签会发布正式版本。

未签名 IPA 需自签后安装，可用 [AltStore](https://altstore.io) / [Sideloadly](https://sideloadly.io) / TrollStore 等。

### 本地开发

```bash
brew install xcodegen
xcodegen generate
open Afterglow.xcodeproj
```

在 Xcode 的 Signing & Capabilities 中选择你的 Team，即可真机运行。要求 iOS 17+。

## 目录

```
Afterglow/
  App/        入口、Tab、地点选择状态
  Models/     云场网格、SwiftData 记录
  Services/   Open-Meteo、太阳位置、霞光评分、定位、通知
  Theme/      配色与色带
  Views/      今日 / 地图 / 记录 / 设置
project.yml   XcodeGen 配置
```
