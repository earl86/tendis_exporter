// 引入最新的 grafana/grafonnet 库
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local config = import '../config.libsonnet';

// 定义一个辅助函数，用于生成 Prometheus 的 Target，让代码看起来非常清爽
local target(expr, legend, refId='A') = {
  expr: expr,
  legendFormat: legend,
  refId: refId,
};

// 自动布局辅助函数：使用 std.foldl 自动计算每个 panel 的 y 坐标
local autoLayout(panels) =
  std.foldl(function(acc, panel)
    {
      local y = acc.y,
      local h = panel.gridPos.h,
      panels: acc.panels + [panel + { gridPos+: { y: y } }],
      y: if h == 1 then y + 1 else y + h,
    }
  , panels, { panels: [], y: 0 }).panels;

// 1. Dashboard 基础构建
g.dashboard.new(config._dashboard.title)

// 2. 强行注入所有 Dashboard 级别的复杂配置（完美绕过缺失的 withX 方法）
+ {
  uid: config._dashboard.uid,
  tags: config._dashboard.tags,
  editable: true,
  refresh: config._dashboard.refresh,
  time: { from: config._dashboard.timeFrom, to: 'now' },
  timepicker: {
    refresh_intervals: ['5s', '10s', '30s', '1m', '5m', '15m', '30m', '1h', '2h', '1d'],
    time_options: ['5m', '15m', '1h', '6h', '12h', '24h', '2d', '7d', '30d'],
  },
  templating: {
    list: [
      { current: { text: 'Prometheus', value: 'Prometheus' }, hide: 0, includeAll: false, label: 'Data Source', multi: false, name: 'datasource', query: 'prometheus', refresh: 1, type: 'datasource' },
      { allValue: null, datasource: 'Prometheus', definition: 'label_values(tendis_exporter_up, instance)', hide: 0, includeAll: true, label: 'Instance', multi: true, name: 'instance', query: { query: 'label_values(tendis_exporter_up, instance)', refId: 'StandardVariableQuery' }, refresh: 1, sort: 1, type: 'query' }
    ],
  },
  style: 'dark',
  graphTooltip: 1,
  annotations: {
    list: [
      { builtIn: 1, datasource: '-- Grafana --', enable: true, hide: true, iconColor: 'rgba(0, 211, 255, 1)', name: 'Annotations & Alerts', type: 'dashboard' },
    ],
  },
}

// 3. 按照新版的标准语法，通过 withPanels 传入所有的 Panel 配置
+ g.dashboard.withPanels(autoLayout([

  // Row 1: Cluster Overview
  g.panel.row.new('Cluster Overview') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 1: Instance Status
  g.panel.stat.new('Instance Status') + {
    description: 'Tendis instance status', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 0 },
    targets: [target('tendis_exporter_up', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [{ type: 'value', options: { '0': { text: 'DOWN', color: 'red', index: 1 }, '1': { text: 'UP', color: 'green', index: 0 } } }], thresholds: { mode: 'absolute', steps: [{ value: null, color: 'red' }, { value: 1, color: 'green' }] } } }
  },

  // Panel 2: Cluster State
  g.panel.stat.new('Cluster State') + {
    description: 'Cluster state', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 4 },
    targets: [target('tendis_cluster_state', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [{ type: 'value', options: { '0': { text: 'FAIL', color: 'red', index: 1 }, '1': { text: 'OK', color: 'green', index: 0 } } }], thresholds: { mode: 'absolute', steps: [{ value: null, color: 'red' }, { value: 1, color: 'green' }] } } }
  },

  // Panel 3: Replication Role
  g.panel.stat.new('Replication Role') + {
    description: 'Replication role', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 8 },
    targets: [
      target('tendis_replication_role{role="master"} > 0', 'MASTER', 'A'),
      target('tendis_replication_role{role="slave"} > 0', 'SLAVE', 'B')
    ],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, mappings: [{ type: 'value', options: { 'master': { text: 'MASTER', color: 'blue', index: 0 }, 'slave': { text: 'SLAVE', color: 'yellow', index: 1 } } }], thresholds: { mode: 'absolute', steps: [{ value: null, color: 'green' }] } } }
  },

  // Panel 4: Connected Clients
  g.panel.stat.new('Connected Clients') + {
    description: 'Connected clients', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 12 },
    targets: [target('tendis_info_connected_clients', '{{instance}}')],
    options: { colorMode: 'value', graphMode: 'area', orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 5: Cluster Nodes
  g.panel.stat.new('Cluster Nodes') + {
    description: 'Cluster nodes', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 16 },
    targets: [target('tendis_info_cluster_cluster_known_nodes', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 6: Cluster Size
  g.panel.stat.new('Cluster Size') + {
    description: 'Cluster size', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 20 },
    targets: [target('tendis_info_cluster_cluster_size', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Row 2: Performance Metrics
  g.panel.row.new('Performance Metrics') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 7: QPS
  g.panel.timeSeries.new('QPS') + {
    description: 'Instantaneous operations per second', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_total_commands_processed[5m])', 'QPS - {{instance}}', 'A'),
      target('tendis_info_instantaneous_ops_per_sec', 'Instant QPS - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ops' } }
  },

  // Panel 8: Network I/O
  g.panel.timeSeries.new('Network I/O') + {
    description: 'Network input/output rate', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_total_net_input_bytes[5m]) * 8', 'Input - {{instance}}', 'A'),
      target('rate(tendis_info_total_net_output_bytes[5m]) * 8', 'Output - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'binBps' } }
  },

  // Panel 9: Keyspace Hit Rate
  g.panel.timeSeries.new('Keyspace Hit Rate') + {
    description: 'Keyspace hit rate', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('rate(tendis_info_keyspace_hits[5m]) / (rate(tendis_info_keyspace_hits[5m]) + rate(tendis_info_keyspace_misses[5m])) * 100', 'Hit Rate - {{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'percentunit' } }
  },

  // Panel 10: Average Command Latency
  g.panel.timeSeries.new('Average Command Latency') + {
    description: 'Command execution time', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('rate(tendis_info_total_commands_cost_ns[5m]) / rate(tendis_info_total_commands_processed[5m]) / 1e9', 'Avg Command Time - {{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['mean', 'max', 'p95'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 11: Top 10 Commands by QPS
  g.panel.barGauge.new('Top 10 Commands by QPS') + {
    description: 'Top commands by call count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('topk(10, sum by(cmd, instance) (rate(tendis_command_calls_total[5m])))', '{{cmd}} - {{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last'] }, displayMode: 'gradient', orientation: 'horizontal', showValue: 'always' },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ops' } }
  },

  // Panel 12: Top 10 Commands by Latency
  g.panel.barGauge.new('Top 10 Commands by Latency') + {
    description: 'Top commands by latency', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('topk(10, avg by(cmd, instance) (tendis_command_usec_per_call))', '{{cmd}} - {{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last'] }, orientation: 'horizontal', showValue: 'always' },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'µs' } }
  },

  // Panel 13: Commands QPS History (Dynamic)
  g.panel.timeSeries.new('Commands QPS History') + {
    description: 'Historical QPS for all command types (auto-discovered)', datasource: 'Prometheus', gridPos: { h: 10, w: 24, x: 0 },
    targets: [target('sum by(cmd, instance) (rate(tendis_command_calls_total[5m]))', '{{cmd}} - {{instance}}')],
    options: {
      legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max', 'min'], showLegend: true },
      tooltip: { mode: 'multi', sort: 'desc' }
    },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ops', custom: { lineStyle: { fill: 'solid' } }, thresholds: { mode: 'absolute', steps: [{ value: null, color: 'green' }, { value: 1000, color: 'yellow' }, { value: 10000, color: 'red' }] } } }
  },

  // Panel 14: Commands Latency History (Dynamic)
  g.panel.timeSeries.new('Commands Latency History') + {
    description: 'Historical latency for all command types (auto-discovered)', datasource: 'Prometheus', gridPos: { h: 10, w: 24, x: 0 },
    targets: [
      target('rate(tendis_command_usec_total[5m]) / rate(tendis_command_calls_total[5m])', '{{cmd}} - {{instance}}')
    ],
    options: {
      legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max', 'p95'], showLegend: true },
      tooltip: { mode: 'multi', sort: 'desc' }
    },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'µs', custom: { lineStyle: { fill: 'solid' } }, thresholds: { mode: 'absolute', steps: [{ value: null, color: 'green' }, { value: 100, color: 'yellow' }, { value: 1000, color: 'red' }] } } }
  },

  // Row 3: RocksDB Binlog
  g.panel.row.new('RocksDB Binlog') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 15: Binlog Remain
  g.panel.timeSeries.new('Binlog Remain') + {
    description: 'Binlog remain count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('sum by(instance, db) (tendis_binlog_remain)', '{{instance}} - {{db}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 16: Binlog Watermarks
  g.panel.timeSeries.new('Binlog Watermarks') + {
    description: 'Binlog high/low watermarks', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('sum by(instance) (tendis_binlog_BHWM)', 'BHWM - {{instance}}', 'A'),
      target('sum by(instance) (tendis_binlog_BLWM)', 'BLWM - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Row 4: RocksDB Level Stats
  g.panel.row.new('RocksDB Level Stats') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 17: Level Files Count
  g.panel.timeSeries.new('Level Files Count') + {
    description: 'RocksDB level file count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('sum by(instance, level) (tendis_levelstats_num_files)', '{{instance}} - {{level}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 18: Level Size
  g.panel.timeSeries.new('Level Size') + {
    description: 'RocksDB level size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('sum by(instance, level) (tendis_levelstats_bytes)', '{{instance}} - {{level}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Panel 19: Level Entries Count
  g.panel.timeSeries.new('Level Entries Count') + {
    description: 'RocksDB level entries', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('sum by(instance, level) (tendis_levelstats_num_entries)', '{{instance}} - {{level}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 20: Total SST Files Size
  g.panel.stat.new('Total SST Files Size') + {
    description: 'RocksDB total SST files size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_info_rocksdb_total_sst_files_size', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'bytes' } }
  },

  // Row 5: RocksDB Cache & Performance
  g.panel.row.new('RocksDB Cache & Performance') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 21: Block Cache
  g.panel.timeSeries.new('Block Cache') + {
    description: 'Block cache usage', datasource: 'Prometheus', gridPos: { h: 8, w: 8, x: 0 },
    targets: [
      target('tendis_info_rocksdb_blockcache_usage', 'Usage - {{instance}}', 'A'),
      target('tendis_info_rocksdb_blockcache_capacity', 'Capacity - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Panel 22: Row Cache
  g.panel.timeSeries.new('Row Cache') + {
    description: 'Row cache usage', datasource: 'Prometheus', gridPos: { h: 8, w: 8, x: 8 },
    targets: [
      target('tendis_info_rocksdb_rowcache_usage', 'Usage - {{instance}}', 'A'),
      target('tendis_info_rocksdb_rowcache_capacity', 'Capacity - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Panel 23: Block Cache Hit Rate
  g.panel.timeSeries.new('Block Cache Hit Rate') + {
    description: 'Block cache hit rate', datasource: 'Prometheus', gridPos: { h: 8, w: 8, x: 16 },
    targets: [
      target('rate(tendis_info_rocksdb_block_cache_hit_COUNT[5m]) / (rate(tendis_info_rocksdb_block_cache_hit_COUNT[5m]) + rate(tendis_info_rocksdb_block_cache_miss_COUNT[5m])) * 100', 'Data - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_block_cache_index_hit_COUNT[5m]) / (rate(tendis_info_rocksdb_block_cache_index_hit_COUNT[5m]) + rate(tendis_info_rocksdb_block_cache_index_miss_COUNT[5m])) * 100', 'Index - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'percentunit' } }
  },

  // Panel 24: RocksDB I/O
  g.panel.timeSeries.new('RocksDB I/O') + {
    description: 'RocksDB read/write bytes', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_bytes_read_COUNT[5m])', 'Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_bytes_written_COUNT[5m])', 'Write - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // Panel 25: RocksDB Compaction I/O
  g.panel.timeSeries.new('RocksDB Compaction I/O') + {
    description: 'RocksDB compaction bytes', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_compact_read_bytes_COUNT[5m])', 'Compaction Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_compact_write_bytes_COUNT[5m])', 'Compaction Write - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // Panel 26: Bloom Filter Effectiveness
  g.panel.timeSeries.new('Bloom Filter Effectiveness') + {
    description: 'Bloom filter effectiveness', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('rate(tendis_info_rocksdb_bloom_filter_useful_COUNT[5m]) / (rate(tendis_info_rocksdb_bloom_filter_useful_COUNT[5m]) + rate(tendis_info_rocksdb_bloom_filter_full_positive_COUNT[5m])) * 100', 'Useful Rate - {{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'percentunit' } }
  },

  // Panel 27: Estimated Keys
  g.panel.stat.new('Estimated Keys') + {
    description: 'Estimate keys count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_info_rocksdb_estimate_num_keys', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Row 6: Keyspace & TTL
  g.panel.row.new('Keyspace & TTL') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 28: DB Keys
  g.panel.timeSeries.new('DB Keys') + {
    description: 'Keys in database', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('sum by(instance, db) (tendis_db_keys)', '{{instance}} - {{db}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 29: DB Expires
  g.panel.timeSeries.new('DB Expires') + {
    description: 'Expiring keys in database', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('sum by(instance, db) (tendis_db_expires)', '{{instance}} - {{db}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 30: Average TTL
  g.panel.timeSeries.new('Average TTL') + {
    description: 'Average TTL', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('avg by(instance, db) (tendis_db_avg_ttl_seconds)', '{{instance}} - {{db}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 31: Expired Keys Rate
  g.panel.timeSeries.new('Expired Keys Rate') + {
    description: 'Expired keys count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('rate(tendis_info_total_expire_keys[5m])', '{{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['sum', 'rate'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ops' } }
  },

  // Row 7: Replication
  g.panel.row.new('Replication') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 32: Replication Offset Lag (Master)
  g.panel.timeSeries.new('Replication Offset Lag (Master)') + {
    description: 'Replication offset lag (master)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('tendis_info_master_repl_offset - max by(instance) (tendis_slave_offset)', 'Offset Lag - {{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 33: Replication Lag (Slave)
  g.panel.timeSeries.new('Replication Lag (Slave)') + {
    description: 'Replication lag in seconds (slave)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_slave_lag_seconds', '{{instance}} - {{slave_id}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 34: Slave Binlog Lag
  g.panel.timeSeries.new('Slave Binlog Lag') + {
    description: 'Slave binlog lag', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('tendis_slave_binlog_lag_seconds', '{{instance}} - {{slave_id}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 35: Connected Slaves
  g.panel.stat.new('Connected Slaves') + {
    description: 'Connected slaves (master)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_info_connected_slaves', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 36: Master Last I/O (Slave View)
  g.panel.timeSeries.new('Master Last I/O (Slave View)') + {
    description: 'Master last I/O seconds ago (slave)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('tendis_info_master_last_io_seconds_ago', '{{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 37: Slave State
  g.panel.stat.new('Slave State') + {
    description: 'Slave state', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_slave_state', '{{instance}} - {{slave_id}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [{ type: 'value', options: { '0': { text: 'OFFLINE', color: 'red', index: 1 }, '1': { text: 'ONLINE', color: 'green', index: 0 } } }], thresholds: { mode: 'absolute', steps: [{ value: null, color: 'red' }, { value: 1, color: 'green' }] } } }
  },

  // Row 8: Memory & Resources
  g.panel.row.new('Memory & Resources') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 38: Resident Memory
  g.panel.timeSeries.new('Resident Memory') + {
    description: 'Process resident memory', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('tendis_tendis_process_resident_memory_bytes', 'RSS - {{instance}}', 'A'),
      target('tendis_info_used_memory_rss', 'Tendis RSS - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Panel 39: Virtual Memory
  g.panel.timeSeries.new('Virtual Memory') + {
    description: 'Process virtual memory', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('tendis_tendis_process_virtual_memory_bytes', 'Virtual - {{instance}}', 'A'),
      target('tendis_info_used_memory_vir', 'Tendis Virtual - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Panel 40: RocksDB Memory
  g.panel.timeSeries.new('RocksDB Memory') + {
    description: 'RocksDB total memory', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('tendis_info_rocksdb_total_memory', '{{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Panel 41: RocksDB Memtables
  g.panel.timeSeries.new('RocksDB Memtables') + {
    description: 'RocksDB memtables size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_info_rocksdb_size_all_mem_tables', '{{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Row 9: CPU & Process Stats
  g.panel.row.new('CPU & Process Stats') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 42: CPU Usage
  g.panel.timeSeries.new('CPU Usage') + {
    description: 'CPU usage', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('rate(tendis_tendis_process_cpu_seconds_total[5m]) * 100', 'CPU - {{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'percent' } }
  },

  // Panel 43: Process Threads
  g.panel.timeSeries.new('Process Threads') + {
    description: 'Process threads', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_tendis_process_threads_count', '{{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'min', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 44: Context Switches Rate
  g.panel.timeSeries.new('Context Switches Rate') + {
    description: 'Context switches', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_tendis_process_context_switches_voluntary_total[5m])', 'Voluntary - {{instance}}', 'A'),
      target('rate(tendis_tendis_process_context_switches_nonvoluntary_total[5m])', 'Non-Voluntary - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['sum', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ops' } }
  },

  // Panel 45: Page Faults Rate
  g.panel.timeSeries.new('Page Faults Rate') + {
    description: 'Page faults', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_tendis_process_page_faults_minor_total[5m])', 'Minor - {{instance}}', 'A'),
      target('rate(tendis_tendis_process_page_faults_major_total[5m])', 'Major - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['sum', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ops' } }
  },

  // Row 10: Disk I/O
  g.panel.row.new('Disk I/O') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 46: Disk Read I/O
  g.panel.timeSeries.new('Disk Read I/O') + {
    description: 'Disk read I/O', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_tendis_process_io_read_bytes_total[5m])', 'Physical Read - {{instance}}', 'A'),
      target('rate(tendis_tendis_process_io_rchar_bytes_total[5m])', 'Logical Read - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // Panel 47: Disk Write I/O
  g.panel.timeSeries.new('Disk Write I/O') + {
    description: 'Disk write I/O', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_tendis_process_io_write_bytes_total[5m])', 'Physical Write - {{instance}}', 'A'),
      target('rate(tendis_tendis_process_io_wchar_bytes_total[5m])', 'Logical Write - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // Panel 48: I/O Operations Rate
  g.panel.timeSeries.new('I/O Operations Rate') + {
    description: 'I/O operations', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_tendis_process_io_syscr_total[5m])', 'Read Ops - {{instance}}', 'A'),
      target('rate(tendis_tendis_process_io_syscw_total[5m])', 'Write Ops - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['sum', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'iops' } }
  },

  // Panel 49: Block I/O Delay Rate
  g.panel.timeSeries.new('Block I/O Delay Rate') + {
    description: 'Block I/O delay', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('rate(tendis_tendis_process_blkio_delay_seconds_total[5m])', '{{instance}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['sum', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Row 11: System & Cluster Health
  g.panel.row.new('System & Cluster Health') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 50: Uptime
  g.panel.stat.new('Uptime') + {
    description: 'Uptime', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 0 },
    targets: [target('tendis_info_uptime_in_seconds', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 's' } }
  },

  // Panel 51: Total Connections
  g.panel.stat.new('Total Connections') + {
    description: 'Total connections received', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 8 },
    targets: [target('tendis_info_total_connections_received', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 52: Rejected Connections
  g.panel.stat.new('Rejected Connections') + {
    description: 'Rejected connections', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 16 },
    targets: [target('tendis_info_rejected_connections', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 53: Compaction Status
  g.panel.stat.new('Compaction Status') + {
    description: 'Compaction status', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 0 },
    targets: [target('tendis_compaction_status', '{{instance}} - {{status}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [{ type: 'value', options: { 'stopped': { text: 'STOPPED', color: 'gray', index: 1 }, 'running': { text: 'RUNNING', color: 'green', index: 0 } } }], thresholds: { mode: 'absolute', steps: [{ value: null, color: 'gray' }] } } }
  },

  // Panel 54: Time Since Last Compaction
  g.panel.stat.new('Time Since Last Compaction') + {
    description: 'Time since last compaction', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 8 },
    targets: [target('tendis_info_time_since_lastest_compaction', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 's' } }
  },

  // Panel 55: Pending Compaction
  g.panel.stat.new('Pending Compaction') + {
    description: 'Pending compaction bytes', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 16 },
    targets: [target('tendis_info_rocksdb_estimate_pending_compaction_bytes', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'bytes' } }
  },

  // Panel 56: Cluster Slot Distribution
  g.panel.timeSeries.new('Cluster Slot Distribution') + {
    description: 'Cluster slot distribution', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_cluster_cluster_slots_ok', 'OK - {{instance}}', 'A'),
      target('tendis_info_cluster_cluster_slots_pfail', 'PFAIL - {{instance}}', 'B'),
      target('tendis_info_cluster_cluster_slots_fail', 'FAIL - {{instance}}', 'C'),
      target('tendis_info_cluster_cluster_slots_assigend', 'Assigned - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  }
]))

