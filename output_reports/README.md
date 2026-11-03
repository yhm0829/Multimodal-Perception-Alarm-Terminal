# HX21A5 ROI GUI 最终交付工程

本目录是 2026-11-02 整理后的唯一有效交付工程。整理仅涉及交付文件清理、说明统一和错误注释修正；未改动 RTL 功能逻辑，未重新生成位流。

请将整个工程解压到不含中文、空格和特殊符号的短英文路径，例如 `D:\HX21A5`。不要直接在微信接收目录等深层路径中解压；HDMI加密核文件名较长，过深的目录可能触发Windows错误 `0x80010135`。

## 唯一推荐下载位流

- 文件：`HX21A5_ROI_20261102.bit`
- SHA256：`CBAFE4EE7E192BA01726F67994E765649818EBBAEE6D3AD53894022C19A56004`
- 状态：最终交付位流，已完成固化

工程中不保留其他 `.bit` 文件。下载或固化时只使用上述文件。

## 最终实现结果

以下数据以根目录三份最终报告为准：

| 项目 | 使用量 / 总量 | 利用率或裕量 |
|---|---:|---:|
| LUT | 16844 / 19600 | 85.94% |
| REG | 7863 / 19600 | 40.12% |
| BRAM9K | 20 / 64 | 31.25% |
| BRAM32K | 12 / 16 | 75.00% |
| DSP | 11 / 29 | 37.93% |
| PLL | 4 / 4 | 100.00% |
| Setup WNS | — | +0.103 ns |
| Setup TNS | — | 0.000 ns |
| Hold WNS | — | +0.020 ns |
| Hold TNS | — | 0.000 ns |
| Period Check WNS | — | +35.600 ns |

权威报告：`resource.rpt`、`timing.rpt`、`timing_check.rpt`。最终结论以上述根目录报告为准。

## 目录说明

- `fpga/user_source/`：RTL 源码、约束、IP 源文件及初始化资源。
- `fpga/td_project/HX21A5.al`：TD 工程入口。
- `fpga/td_project/al_ip/`：工程所需初始化文件。
- `fpga/td_project/closure/`、`mapped_reset_sync_pair_audited.tcl`、`phase1_complete_timing.sdc`、`read_cycle_pairs.sdc`：实现与时序收敛所需脚本和约束。
- `fpga/td_project/HX21A5_Runs/syn_1/HX21A5.tcl`、`phy_1/HX21A5.tcl`：TD直接打开 `.al` 后必须使用的自定义综合与物理实现流程脚本；目录中不含历史结果。
- `fpga/td_project/build_final.tcl`：生成最终位流和三份最终报告的构建脚本。
- `ROI_Guide.md`：ROI九宫格平移与交互操作说明。
- `THIRD_PARTY_LICENSE.txt`：PAJ7620U2公开寄存器初始化序列的第三方许可说明。
- `verification/`：测试源文件与验证记录。
- `DELIVERY_MANIFEST.txt`：最终保留文件及用途清单。
- `SHA256.csv`：除该清单自身外的全部交付文件校验值。
- `build_summary.json`：位流、资源和时序数据的机器可读汇总。

## 打开与重建

推荐工具版本：Anlogic TD 6.2.1 Engineer 6.2.168.116（工程记录版本 `6.2.168116`）。

1. 直接双击 `fpga/td_project/HX21A5.al`。工程路径为相对于 `.al` 所在目录的 `.`，不依赖固定盘符或用户名；交付包已预置最小运行目录和自定义流程脚本，不得删除其中两个 `HX21A5.tcl`。
2. 如需重新完整构建，使用 `fpga/td_project/build_final.tcl`。重新构建会产生新的运行数据库和位流；未经重新验证，不得替换本交付的推荐位流。

## 使用边界

- 传感器标准右挥：内部码 3，HDMI 显示 `GES:1`，切换到下一张。
- 传感器标准左挥：内部码 4，HDMI 显示 `GES:2`，切换到上一张。
- DIG 开关的流水灯位置不作为本交付功能；共享输出逻辑仅为保持已固化设计不变而保留。
- 告警图标表达相对强弱分级，不表示声源距离或地图定位。

