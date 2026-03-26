local config = import 'config.libsonnet';
local alerts = import 'alerts/alerts.libsonnet';
local rules = import 'rules/rules.libsonnet';
local tendisOverview = import 'dashboards/tendis-overview.libsonnet';

{
  prometheusAlerts: (config + alerts).prometheusAlerts,
  prometheusRules: (config + rules).prometheusRules,

  grafanaDashboards+:: {
    // 这里的 key 会被 mixtool 识别为生成的大盘文件名
    'tendis-overview.json': tendisOverview,
  },
}
