# Tendis Monitoring Mixin

本项目包含了一套完整且高度工程化的 Tendis（基于 RocksDB 的 Redis 兼容数据库）监控解决方案。包含预计算的 Prometheus 记录规则（Recording Rules）、多维度的告警规则（Alerting Rules）以及现代化的 Grafana 监控大盘（Dashboard）。

本项目基于 [Jsonnet](https://jsonnet.org/) 语言，采用最新的官方 [Grafonnet](https://github.com/grafana/grafonnet) 库编写，并通过 `mixtool` 进行统一构建，具备极强的可维护性与扩展性。

## 目录结构

·
├── Makefile                     # 自动化构建脚本（包含环境依赖自动探测与安装）
├── mixin.libsonnet              # Mixin 项目统一入口文件
├── config.libsonnet             # 全局配置中心（统一管理告警阈值、大盘元数据等）
├── alerts/
│   └── alerts.libsonnet         # Prometheus 告警规则定义
├── rules/
│   └── rules.libsonnet          # Prometheus 预计算记录规则定义
├── dashboards/
│   └── tendis-overview.libsonnet# Grafana 大盘面板布局与视图定义
├── jsonnetfile.json             # jb (jsonnet-bundler) 依赖声明文件
└── vendor/                      # 自动生成的第三方依赖库目录（请勿提交至 Git）

## 快速开始

本项目实现了**“一键傻瓜式构建”**。你不需要手动配置复杂的 Jsonnet 环境，只要你的机器上安装了 `Go`，即可直接编译。

### 1. 编译生成配置

在项目根目录下执行：

```bash
make build
