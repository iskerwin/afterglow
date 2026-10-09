import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ForecastStore.self) private var store
    @Environment(PlaceSelection.self) private var places
    @AppStorage(NotificationScheduler.enabledKey) private var notifyEnabled = false
    @AppStorage(NotificationScheduler.thresholdKey) private var threshold = 60.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("霞光提醒", isOn: $notifyEnabled)
                        .onChange(of: notifyEnabled) { _, on in
                            Task {
                                if on { notifyEnabled = await NotificationScheduler.requestPermission() }
                                await reschedule()
                            }
                        }
                    if notifyEnabled {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("指数达到")
                                Spacer()
                                ScoreChip(score: threshold)
                            }
                            Slider(value: $threshold, in: 30...90, step: 5, onEditingChanged: { editing in
                                if !editing { Task { await reschedule() } }
                            })
                        }
                    }
                } header: {
                    Text("通知")
                } footer: {
                    Text("预测指数达到阈值时，在日出 / 日落前 1 小时提醒你。打开 App 刷新时会重新安排。")
                }

                Section("霞光指数是怎么算的") {
                    explain("cloud.fill", "画布", "高云、中云覆盖 40%–80% 最理想，太晴没有云可染色，太厚透不过光。")
                    explain("sun.haze.fill", "光路", "日落时阳光贴着地平线从太阳方向照来，沿太阳方位角采样 30–115 km 外的低云，越少越好。这是火烧云最关键的一环。")
                    explain("eye.fill", "视线", "本地低云太多会把天空整个盖住。")
                    explain("aqi.medium", "大气", "能见度、湿度与气溶胶。适量气溶胶让颜色更红，霾太重则发灰。")
                    explain("cloud.rain.fill", "降水", "正在下雨扣分；雨后 1–3 小时放晴加分。")
                }

                Section("等级") {
                    ForEach(GlowLevel.allCases, id: \.self) { l in
                        HStack {
                            ScoreChip(score: Double(l.rawValue) * 20 + 10)
                            Text(l.advice).font(.subheadline)
                        }
                    }
                }

                Section {
                    Link(destination: URL(string: "https://open-meteo.com/")!) {
                        Label("天气数据：Open-Meteo（CC BY 4.0）", systemImage: "link")
                    }
                    Link(destination: URL(string: "https://github.com/iskerwin/afterglow")!) {
                        Label("GitHub 源代码", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } footer: {
                    Text("预测基于数值天气模式，仅供参考。霞光很难预测，多出门看看天 :)")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .tint(Theme.accent)
    }

    private func explain(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func reschedule() async {
        await NotificationScheduler.reschedule(events: store.events, placeName: places.selected?.name ?? "")
    }
}
