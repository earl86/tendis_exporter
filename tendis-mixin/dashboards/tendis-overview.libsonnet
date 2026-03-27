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

  // RocksDB KVStore Count
  g.panel.stat.new('RocksDB KVStore Count') + {
    description: 'RocksDB kvstore count', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 0 },
    targets: [target('tendis_info_rocksdb_kvstore_count', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 2: Cluster State
  g.panel.stat.new('Cluster State') + {
    description: 'Cluster state and enabled status', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 4 },
    targets: [
      target('tendis_cluster_state', 'State - {{instance}}', 'A'),
      target('tendis_info_cluster_enabled', 'Enabled - {{instance}}', 'B')
    ],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [{ type: 'value', options: { '0': { text: 'FAIL', color: 'red', index: 1 }, '1': { text: 'OK', color: 'green', index: 0 } } }], thresholds: { mode: 'absolute', steps: [{ value: null, color: 'red' }, { value: 1, color: 'green' }] } } }
  },

  // Panel 6: Cluster Size
  g.panel.stat.new('Cluster Size') + {
    description: 'Cluster size', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 20 },
    targets: [target('tendis_info_cluster_cluster_size', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 5: Cluster Nodes
  g.panel.stat.new('Cluster Nodes') + {
    description: 'Cluster nodes', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 16 },
    targets: [target('tendis_info_cluster_cluster_known_nodes', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // Panel 7: Cluster Epoch
  g.panel.stat.new('Cluster Epoch') + {
    description: 'Cluster current epoch and my epoch', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 16 },
    targets: [
      target('tendis_info_cluster_cluster_current_epoch', 'Current - {{instance}}', 'A'),
      target('tendis_info_cluster_cluster_my_epoch', 'My - {{instance}}', 'B')
    ],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
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

  // Panel 4: Backup Status
  g.panel.stat.new('Backup Status') + {
    description: 'Backup running status (derived from status="no" metric)', datasource: 'Prometheus', gridPos: { h: 4, w: 4, x: 12 },
    targets: [target('tendis_backup_running{status="no"}', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, mappings: [{ type: 'value', options: { '0': { text: 'RUNNING', color: 'blue', index: 0 }, '1': { text: 'IDLE', color: 'gray', index: 1 } } }], thresholds: { mode: 'absolute', steps: [{ value: null, color: 'gray' }, { value: 1, color: 'green' }] } } }
  },

  // Panel 5: Connected Clients
  g.panel.stat.new('Connected Clients') + {
    description: 'Connected clients breakdown', datasource: 'Prometheus', gridPos: { h: 4, w: 12, x: 0 },
    targets: [
      target('tendis_info_connected_clients', 'Total - {{instance}}', 'A'),
      target('tendis_info_cluster_clients', 'Cluster - {{instance}}', 'B'),
      target('tendis_info_local_clients', 'Local - {{instance}}', 'C'),
      target('tendis_info_net_clients', 'Net - {{instance}}', 'D')
    ],
    options: { colorMode: 'value', graphMode: 'area', orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 8: Cluster Messages
  g.panel.timeSeries.new('Cluster Messages') + {
    description: 'Cluster bus messages (sent/received)', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_cluster_cluster_stats_messages_received', 'Received - {{instance}}', 'A'),
      target('tendis_info_cluster_cluster_stats_messages_sent', 'Sent - {{instance}}', 'B'),
      target('tendis_info_cluster_cluster_stats_messages_ping_received', 'Ping In - {{instance}}', 'C'),
      target('tendis_info_cluster_cluster_stats_messages_ping_sent', 'Ping Out - {{instance}}', 'D'),
      target('tendis_info_cluster_cluster_stats_messages_pong_received', 'Pong In - {{instance}}', 'E'),
      target('tendis_info_cluster_cluster_stats_messages_pong_sent', 'Pong Out - {{instance}}', 'F'),
      target('tendis_info_cluster_cluster_stats_messages_meet_received', 'Meet - {{instance}}', 'G'),
      target('tendis_info_cluster_cluster_stats_messages_auth_req_received', 'Auth Req - {{instance}}', 'H'),
      target('tendis_info_cluster_cluster_stats_messages_auth_ack_received', 'Auth Ack - {{instance}}', 'I'),
      target('tendis_info_cluster_cluster_stats_messages_fail_received', 'Fail - {{instance}}', 'J')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'rate'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 9: Sync Status
  g.panel.timeSeries.new('Sync Status') + {
    description: 'Sync full/partial ok/partial err', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_sync_full', 'Full Sync - {{instance}}', 'A'),
      target('tendis_info_sync_partial_ok', 'Partial OK - {{instance}}', 'B'),
      target('tendis_info_sync_partial_err', 'Partial Err - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 10: Schedule Num
  g.panel.timeSeries.new('Schedule Num') + {
    description: 'Total scheduled tasks count', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_scheduleNum', 'Schedule Num - {{instance}}', 'A'),
      target('rate(tendis_info_scheduleNum[5m])', 'Schedule Rate - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Row 2: Performance Metrics
  g.panel.row.new('Performance Metrics') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 7: Error Metrics
  g.panel.timeSeries.new('Error Metrics') + {
    description: 'Internal errors, RocksDB bg errors, keyspace wrong version, unseen commands', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('tendis_info_internalErrors', 'Internal Errors - {{instance}}', 'A'),
      target('tendis_info_rocksdb_bg_error_count', 'RocksDB BG Error - {{instance}}', 'B'),
      target('tendis_info_keyspace_wrong_versionep', 'Keyspace Wrong Version - {{instance}}', 'C'),
      target('tendis_info_cmdstat_unseen_num', 'Unseen Cmds - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 8: Slowlog Last ID
  g.panel.stat.new('Slowlog Last ID') + {
    description: 'Slowlog last entry ID', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('tendis_slowlog_last_id', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 9: QPS
  g.panel.timeSeries.new('QPS') + {
    description: 'Instantaneous operations per second, workpool executed and queue', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_total_commands_processed[5m])', 'QPS - {{instance}}', 'A'),
      target('tendis_info_instantaneous_ops_per_sec', 'Instant QPS - {{instance}}', 'B'),
      target('tendis_info_commands_in_queue', 'In Queue - {{instance}}', 'C'),
      target('rate(tendis_info_commands_executed_in_workpool[5m])', 'Workpool Exec Rate - {{instance}}', 'D')
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

  // Panel 9: Instantaneous Network KBps
  g.panel.timeSeries.new('Instantaneous Network KBps') + {
    description: 'Instantaneous network input/output KBps', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('tendis_info_instantaneous_input_kbps', 'Input KBps - {{instance}}', 'A'),
      target('tendis_info_instantaneous_output_kbps', 'Output KBps - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Kbits' } }
  },

  // Panel 10: Invalid & Sticky Packets
  g.panel.timeSeries.new('Invalid & Sticky Packets') + {
    description: 'Invalid and sticky packets count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_total_invalid_packets[5m])', 'Invalid Packets - {{instance}}', 'A'),
      target('rate(tendis_info_total_stricky_packets[5m])', 'Sticky Packets - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'sum'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ops' } }
  },

  // Panel 11: Keyspace Hit Rate
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

  // Panel 11: Command Cost Breakdown
  g.panel.timeSeries.new('Command Cost Breakdown') + {
    description: 'Average command cost breakdown by phase (ns)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('tendis_info_avg_commands_cost_ns', 'Total - {{instance}}', 'A'),
      target('tendis_info_avg_commands_execute_cost_ns', 'Execute - {{instance}}', 'B'),
      target('tendis_info_avg_commands_send_packet_cost_ns', 'SendPacket - {{instance}}', 'C'),
      target('tendis_info_avg_commands_workpool_execute_cost_ns', 'WorkpoolExecute - {{instance}}', 'D'),
      target('tendis_info_avg_commands_workpool_queue_cost_ns', 'WorkpoolQueue - {{instance}}', 'E')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'ns' } }
  },

  // Panel 12: Top 10 Commands by QPS
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

  // Panel 15: Scanner Matrix Avg Time
  g.panel.timeSeries.new('Scanner Matrix Avg Time') + {
    description: 'Scanner average execute time and queue time per task', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_scanner_matrix_executeTime[5m]) / rate(tendis_info_scanner_matrix_executed[5m])', 'Avg Execute Time - {{instance}}', 'A'),
      target('rate(tendis_info_scanner_matrix_queueTime[5m]) / rate(tendis_info_scanner_matrix_executed[5m])', 'Avg Queue Time - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 16: Scanner Matrix Queue & Executing
  g.panel.timeSeries.new('Scanner Matrix Queue & Executing') + {
    description: 'Scanner current queue depth and executing count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('tendis_info_scanner_matrix_inQueue', 'In Queue - {{instance}}', 'A'),
      target('tendis_info_scanner_matrix_executing', 'Executing - {{instance}}', 'B'),
      target('rate(tendis_info_scanner_matrix_executed[5m])', 'Execute Rate - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 17: Deleter Matrix Avg Time
  g.panel.timeSeries.new('Deleter Matrix Avg Time') + {
    description: 'Deleter average execute time and queue time per task', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_deleter_matrix_executeTime[5m]) / rate(tendis_info_deleter_matrix_executed[5m])', 'Avg Execute Time - {{instance}}', 'A'),
      target('rate(tendis_info_deleter_matrix_queueTime[5m]) / rate(tendis_info_deleter_matrix_executed[5m])', 'Avg Queue Time - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 18: Deleter Matrix Queue & Executing
  g.panel.timeSeries.new('Deleter Matrix Queue & Executing') + {
    description: 'Deleter current queue depth and executing count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('tendis_info_deleter_matrix_inQueue', 'In Queue - {{instance}}', 'A'),
      target('tendis_info_deleter_matrix_executing', 'Executing - {{instance}}', 'B'),
      target('rate(tendis_info_deleter_matrix_executed[5m])', 'Execute Rate - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
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
    description: 'Binlog high/low watermarks, min and save offset', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('sum by(instance) (tendis_binlog_BHWM)', 'BHWM - {{instance}}', 'A'),
      target('sum by(instance) (tendis_binlog_BLWM)', 'BLWM - {{instance}}', 'B'),
      target('sum by(instance, db) (tendis_binlog_min)', 'Min - {{instance}} - {{db}}', 'C'),
      target('sum by(instance, db) (tendis_binlog_save)', 'Save - {{instance}} - {{db}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max', 'mean'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Row 4: RocksDB Level Stats
  g.panel.row.new('RocksDB Level Stats') + { gridPos: { h: 1, w: 24, x: 0 }, collapsed: false },

  // Panel 17: RocksDB Level Hit Count
  g.panel.timeSeries.new('RocksDB Level Hit Count') + {
    description: 'RocksDB L0/L1/L2+ hit count', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_l0_hit_COUNT[5m])', 'L0 Hit - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_l1_hit_COUNT[5m])', 'L1 Hit - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_l2andup_hit_COUNT[5m])', 'L2+ Hit - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 18: RocksDB Stall & Slowdown
  g.panel.timeSeries.new('RocksDB Stall & Slowdown') + {
    description: 'RocksDB memtable flush pending, L0 stall and slowdown', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_rocksdb_mem_table_flush_pending', 'Flush Pending - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_l0_num_files_stall_micros_COUNT[5m])', 'L0 Stall - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_l0_slowdown_micros_COUNT[5m])', 'L0 Slowdown - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_stall_micros_COUNT[5m])', 'Stall Micros - {{instance}}', 'D'),
      target('tendis_info_rocksdb_compaction_pending', 'Compaction Pending - {{instance}}', 'E')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 19: Level Files Count
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

  // Panel 20: Level Deletions
  g.panel.timeSeries.new('Level Deletions') + {
    description: 'RocksDB level deletions', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [target('sum by(instance, db, level) (tendis_levelstats_num_deletions)', '{{instance}} - {{db}} - {{level}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 21: Level Range Deletions
  g.panel.timeSeries.new('Level Range Deletions') + {
    description: 'RocksDB level range deletions', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [target('sum by(instance, db, level) (tendis_levelstats_num_range_deletions)', '{{instance}} - {{db}} - {{level}}')],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 22: Total SST Files Size
  g.panel.stat.new('Total SST Files Size') + {
    description: 'RocksDB total/live/binlog SST files size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('tendis_info_rocksdb_total_sst_files_size', 'Total - {{instance}}', 'A'),
      target('tendis_info_rocksdb_live_sst_files_size', 'Live - {{instance}}', 'B'),
      target('tendis_info_rocksdb_binlogcf_sst_files_size', 'BinlogCF - {{instance}}', 'C')
    ],
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

  // Block Cache Add Operations
  g.panel.timeSeries.new('Block Cache Add Operations') + {
    description: 'Block cache add, add_failures, add_redundant, and compressed add operations', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_block_cache_add_COUNT[5m])', 'Add - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_block_cache_add_failures_COUNT[5m])', 'Add Failures - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_block_cache_add_redundant_COUNT[5m])', 'Add Redundant - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_block_cache_data_add_COUNT[5m])', 'Data Add - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_block_cache_data_add_redundant_COUNT[5m])', 'Data Redundant - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_block_cache_filter_add_COUNT[5m])', 'Filter Add - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_block_cache_filter_add_redundant_COUNT[5m])', 'Filter Redundant - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_block_cache_index_add_COUNT[5m])', 'Index Add - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_block_cache_index_add_redundant_COUNT[5m])', 'Index Redundant - {{instance}}', 'I'),
      target('rate(tendis_info_rocksdb_block_cache_compression_dict_add_COUNT[5m])', 'Compression Dict Add - {{instance}}', 'J'),
      target('rate(tendis_info_rocksdb_block_cache_compression_dict_add_redundant_COUNT[5m])', 'Compression Dict Redundant - {{instance}}', 'K'),
      target('rate(tendis_info_rocksdb_block_cachecompressed_add_COUNT[5m])', 'Compressed Add - {{instance}}', 'L'),
      target('rate(tendis_info_rocksdb_block_cachecompressed_add_failures_COUNT[5m])', 'Compressed Add Failures - {{instance}}', 'M')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Block Cache Bytes
  g.panel.timeSeries.new('Block Cache Bytes') + {
    description: 'Block cache bytes read, write, insert, evict by type', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_block_cache_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_block_cache_bytes_write_COUNT[5m])', 'Bytes Write - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_block_cache_data_bytes_insert_COUNT[5m])', 'Data Bytes Insert - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_block_cache_filter_bytes_insert_COUNT[5m])', 'Filter Bytes Insert - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_block_cache_filter_bytes_evict_COUNT[5m])', 'Filter Bytes Evict - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_block_cache_index_bytes_insert_COUNT[5m])', 'Index Bytes Insert - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_block_cache_index_bytes_evict_COUNT[5m])', 'Index Bytes Evict - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_block_cache_compression_dict_bytes_insert_COUNT[5m])', 'Compression Dict Bytes Insert - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_block_cache_compression_dict_bytes_evict_COUNT[5m])', 'Compression Dict Bytes Evict - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // Block Cache Hit/Miss
  g.panel.timeSeries.new('Block Cache Hit/Miss') + {
    description: 'Block cache hit and miss counts by type (total, data, index, filter, compressed, compression_dict)', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_block_cache_hit_COUNT[5m])', 'Total Hit - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_block_cache_miss_COUNT[5m])', 'Total Miss - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_block_cache_data_hit_COUNT[5m])', 'Data Hit - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_block_cache_data_miss_COUNT[5m])', 'Data Miss - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_block_cache_index_hit_COUNT[5m])', 'Index Hit - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_block_cache_index_miss_COUNT[5m])', 'Index Miss - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_block_cache_filter_hit_COUNT[5m])', 'Filter Hit - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_block_cache_filter_miss_COUNT[5m])', 'Filter Miss - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_block_cachecompressed_hit_COUNT[5m])', 'Compressed Hit - {{instance}}', 'I'),
      target('rate(tendis_info_rocksdb_block_cachecompressed_miss_COUNT[5m])', 'Compressed Miss - {{instance}}', 'J'),
      target('rate(tendis_info_rocksdb_block_cache_compression_dict_hit_COUNT[5m])', 'Compression Dict Hit - {{instance}}', 'K'),
      target('rate(tendis_info_rocksdb_block_cache_compression_dict_miss_COUNT[5m])', 'Compression Dict Miss - {{instance}}', 'L')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // All Cache Hit/Miss
  g.panel.timeSeries.new('All Cache Hit/Miss') + {
    description: 'Memtable, row cache, persistent cache, sim block cache hit and miss counts', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_memtable_hit_COUNT[5m])', 'Memtable Hit - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_memtable_miss_COUNT[5m])', 'Memtable Miss - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_row_cache_hit_COUNT[5m])', 'Row Cache Hit - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_row_cache_miss_COUNT[5m])', 'Row Cache Miss - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_persistent_cache_hit_COUNT[5m])', 'Persistent Cache Hit - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_persistent_cache_miss_COUNT[5m])', 'Persistent Cache Miss - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_sim_block_cache_hit_COUNT[5m])', 'Sim Block Cache Hit - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_sim_block_cache_miss_COUNT[5m])', 'Sim Block Cache Miss - {{instance}}', 'H')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
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

  // Cache Pinned Usage
  g.panel.timeSeries.new('Cache Pinned Usage') + {
    description: 'Block cache and row cache pinned memory usage', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_rocksdb_blockcache_pinnedusage', 'Block Cache Pinned - {{instance}}', 'A'),
      target('tendis_info_rocksdb_rowcache_pinnedusage', 'Row Cache Pinned - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // RocksDB Estimate Data
  g.panel.timeSeries.new('RocksDB Estimate Data') + {
    description: 'Estimated live data size and pending compaction bytes', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_rocksdb_estimate_live_data_size', 'Live Data Size - {{instance}}', 'A'),
      target('tendis_info_rocksdb_estimate_pending_compaction_bytes', 'Pending Compaction Bytes - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // RocksDB Estimate Keys & Readers
  g.panel.timeSeries.new('RocksDB Estimate Keys & Readers') + {
    description: 'Estimated keys count and table readers memory', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('tendis_info_rocksdb_estimate_num_keys', 'Estimate Num Keys - {{instance}}', 'A'),
      target('tendis_info_rocksdb_estimate_num_keys_binlogcf', 'Estimate Num Keys BinlogCF - {{instance}}', 'B'),
      target('tendis_info_rocksdb_estimate_table_readers_mem', 'Table Readers Mem - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 26: Bloom Filter Effectiveness
  g.panel.timeSeries.new('Bloom Filter Effectiveness') + {
    description: 'Bloom filter effectiveness', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_bloom_filter_useful_COUNT[5m]) / (rate(tendis_info_rocksdb_bloom_filter_useful_COUNT[5m]) + rate(tendis_info_rocksdb_bloom_filter_full_positive_COUNT[5m])) * 100', 'Useful Rate - {{instance}}'),
      target('rate(tendis_info_rocksdb_bloom_filter_full_true_positive_COUNT[5m])', 'Full True Positive - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_bloom_filter_micros_COUNT[5m])', 'Micros - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_bloom_filter_prefix_checked_COUNT[5m])', 'Prefix Checked - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_bloom_filter_prefix_useful_COUNT[5m])', 'Prefix Useful - {{instance}}', 'E')
    ],
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

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB Error Handler
  g.panel.timeSeries.new('RocksDB Error Handler') + {
    description: 'RocksDB error handler stats (autoresume and background error counts)', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_error_handler_autoresume_count_COUNT[5m])', 'Autoresume Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_error_handler_autoresume_retry_total_count_COUNT[5m])', 'Autoresume Retry Total - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_error_handler_autoresume_success_count_COUNT[5m])', 'Autoresume Success - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_error_handler_bg_errro_count_COUNT[5m])', 'BG Error Count - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_error_handler_bg_io_errro_count_COUNT[5m])', 'BG IO Error Count - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_error_handler_bg_retryable_io_errro_count_COUNT[5m])', 'BG Retryable IO Error - {{instance}}', 'F')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB Transaction Overhead
  g.panel.timeSeries.new('RocksDB Transaction Overhead') + {
    description: 'RocksDB transaction stats (get tryagain and overhead)', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_txn_get_tryagain_COUNT[5m])', 'Txn Get Tryagain - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_txn_overhead_duplicate_key_COUNT[5m])', 'Overhead Duplicate Key - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_txn_overhead_mutex_old_commit_map_COUNT[5m])', 'Overhead Mutex Old Commit Map - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_txn_overhead_mutex_prepare_COUNT[5m])', 'Overhead Mutex Prepare - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_txn_overhead_mutex_snapshot_COUNT[5m])', 'Overhead Mutex Snapshot - {{instance}}', 'E')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB WAL & Write
  g.panel.timeSeries.new('RocksDB WAL & Write') + {
    description: 'RocksDB WAL bytes, write stats (self, other, wal, timeout)', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_wal_bytes_COUNT[5m])', 'WAL Bytes - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_wal_synced_COUNT[5m])', 'WAL Synced - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_write_self_COUNT[5m])', 'Write Self - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_write_other_COUNT[5m])', 'Write Other - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_write_wal_COUNT[5m])', 'Write WAL - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_write_timeout_COUNT[5m])', 'Write Timeout - {{instance}}', 'F')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB File Operations
  g.panel.timeSeries.new('RocksDB File Operations') + {
    description: 'RocksDB file opens, closes and errors', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_no_file_opens_COUNT[5m])', 'File Opens - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_no_file_closes_COUNT[5m])', 'File Closes - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_no_file_errors_COUNT[5m])', 'File Errors - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB Number Stats
  g.panel.timeSeries.new('RocksDB Number Stats') + {
    description: 'RocksDB block compress/decompress, db seek/next/prev, keys read/write, merge, multiget, iter skip, etc.', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_number_block_compressed_COUNT[5m])', 'Block Compressed - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_number_block_decompressed_COUNT[5m])', 'Block Decompressed - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_number_block_not_compressed_COUNT[5m])', 'Block Not Compressed - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_number_db_next_COUNT[5m])', 'DB Next - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_number_db_next_found_COUNT[5m])', 'DB Next Found - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_number_db_prev_COUNT[5m])', 'DB Prev - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_number_db_prev_found_COUNT[5m])', 'DB Prev Found - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_number_db_seek_COUNT[5m])', 'DB Seek - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_number_db_seek_found_COUNT[5m])', 'DB Seek Found - {{instance}}', 'I'),
      target('rate(tendis_info_rocksdb_number_deletes_filtered_COUNT[5m])', 'Deletes Filtered - {{instance}}', 'J'),
      target('rate(tendis_info_rocksdb_number_direct_load_table_properties_COUNT[5m])', 'Direct Load Props - {{instance}}', 'K'),
      target('rate(tendis_info_rocksdb_number_iter_skip_COUNT[5m])', 'Iter Skip - {{instance}}', 'L'),
      target('rate(tendis_info_rocksdb_number_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'M'),
      target('rate(tendis_info_rocksdb_number_keys_updated_COUNT[5m])', 'Keys Updated - {{instance}}', 'N'),
      target('rate(tendis_info_rocksdb_number_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'O'),
      target('rate(tendis_info_rocksdb_number_merge_failures_COUNT[5m])', 'Merge Failures - {{instance}}', 'P'),
      target('rate(tendis_info_rocksdb_number_multiget_bytes_read_COUNT[5m])', 'Multiget Bytes Read - {{instance}}', 'Q'),
      target('rate(tendis_info_rocksdb_number_multiget_get_COUNT[5m])', 'Multiget Get - {{instance}}', 'R'),
      target('rate(tendis_info_rocksdb_number_multiget_keys_found_COUNT[5m])', 'Multiget Keys Found - {{instance}}', 'S'),
      target('rate(tendis_info_rocksdb_number_multiget_keys_read_COUNT[5m])', 'Multiget Keys Read - {{instance}}', 'T'),
      target('rate(tendis_info_rocksdb_number_rate_limiter_drains_COUNT[5m])', 'Rate Limiter Drains - {{instance}}', 'U'),
      target('rate(tendis_info_rocksdb_number_reseeks_iteration_COUNT[5m])', 'Reseeks Iteration - {{instance}}', 'V'),
      target('rate(tendis_info_rocksdb_number_superversion_acquires_COUNT[5m])', 'Superversion Acquires - {{instance}}', 'W'),
      target('rate(tendis_info_rocksdb_number_superversion_cleanups_COUNT[5m])', 'Superversion Cleanups - {{instance}}', 'X'),
      target('rate(tendis_info_rocksdb_number_superversion_releases_COUNT[5m])', 'Superversion Releases - {{instance}}', 'Y')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB Compaction Bytes Detail
  g.panel.timeSeries.new('RocksDB Compaction Bytes Detail') + {
    description: 'RocksDB compaction read/write bytes by type (total, marked, periodic, ttl)', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_compact_read_bytes_COUNT[5m])', 'Read Total - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_compact_read_marked_bytes_COUNT[5m])', 'Read Marked - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_compact_read_periodic_bytes_COUNT[5m])', 'Read Periodic - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_compact_read_ttl_bytes_COUNT[5m])', 'Read TTL - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_compact_write_bytes_COUNT[5m])', 'Write Total - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_compact_write_marked_bytes_COUNT[5m])', 'Write Marked - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_compact_write_periodic_bytes_COUNT[5m])', 'Write Periodic - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_compact_write_ttl_bytes_COUNT[5m])', 'Write TTL - {{instance}}', 'H')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // RocksDB Compaction Key Drops
  g.panel.timeSeries.new('RocksDB Compaction Key Drops') + {
    description: 'RocksDB compaction key drop stats, cancelled count and filter count', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_compaction_cancelled_COUNT[5m])', 'Cancelled - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_compaction_key_drop_new_COUNT[5m])', 'Key Drop New - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_compaction_key_drop_obsolete_COUNT[5m])', 'Key Drop Obsolete - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_compaction_key_drop_range_del_COUNT[5m])', 'Key Drop Range Del - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_compaction_key_drop_user_COUNT[5m])', 'Key Drop User - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_compaction_optimized_del_drop_obsolete_COUNT[5m])', 'Optimized Del Drop Obsolete - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_compaction_range_del_drop_obsolete_COUNT[5m])', 'Range Del Drop Obsolete - {{instance}}', 'G'),
      target('tendis_info_rocksdb_compaction_filter_count', 'Filter Count - {{instance}}', 'H'),
      target('tendis_info_rocksdb_compaction_kv_expired_count', 'KV Expired - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB Iterator Stats
  g.panel.timeSeries.new('RocksDB Iterator Stats') + {
    description: 'RocksDB iterator created/deleted/active and skip count', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_num_iterator_created_COUNT[5m])', 'Iterator Created - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_num_iterator_deleted_COUNT[5m])', 'Iterator Deleted - {{instance}}', 'B'),
      target('tendis_info_rocksdb_num_iterators_COUNT', 'Active Iterators - {{instance}}', 'C'),
      target('tendis_info_rocksdb_number_iter_skip', 'Iter Skip - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB Bytes I/O
  g.panel.timeSeries.new('RocksDB Bytes I/O') + {
    description: 'RocksDB total bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // RocksDB Iter & Flush Bytes
  g.panel.timeSeries.new('RocksDB Iter & Flush Bytes') + {
    description: 'RocksDB iterator bytes read and flush bytes written', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_db_iter_bytes_read_COUNT[5m])', 'Iter Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_flush_write_bytes_COUNT[5m])', 'Flush Write Bytes - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // Memtable Flush Stats
  g.panel.timeSeries.new('Memtable Flush Stats') + {
    description: 'Memtable garbage and payload bytes at flush', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_memtable_garbage_bytes_at_flush_COUNT[5m])', 'Garbage Bytes at Flush - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_memtable_payload_bytes_at_flush_COUNT[5m])', 'Payload Bytes at Flush - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // Read Amplification
  g.panel.timeSeries.new('Read Amplification') + {
    description: 'RocksDB read amplification useful and total read bytes', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_read_amp_estimate_useful_bytes_COUNT[5m])', 'Useful Read Bytes - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_read_amp_total_read_bytes_COUNT[5m])', 'Total Read Bytes - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // File Lifecycle
  g.panel.timeSeries.new('File Lifecycle') + {
    description: 'RocksDB files deleted immediately and marked as trash', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_files_deleted_immediately_COUNT[5m])', 'Deleted Immediately - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_files_marked_trash_COUNT[5m])', 'Marked Trash - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // RocksDB Time Costs
  g.panel.timeSeries.new('RocksDB Time Costs') + {
    description: 'RocksDB operation latency: merge, filter, rate limit delay, memtable compaction, mutex wait', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_merge_operation_time_nanos_COUNT[5m])', 'Merge Op Time (ns) - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_filter_operation_time_nanos_COUNT[5m])', 'Filter Op Time (ns) - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_rate_limit_delay_millis_COUNT[5m])', 'Rate Limit Delay (ms) - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_memtable_compaction_micros_COUNT[5m])', 'Memtable Compaction (us) - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_db_mutex_wait_micros_COUNT[5m])', 'DB Mutex Wait (us) - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_getupdatessince_calls_COUNT[5m])', 'GetUpdatesSince Calls - {{instance}}', 'F')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
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
    description: 'Expired and deleting keys', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_total_expire_keys[5m])', 'Expired - {{instance}}', 'A'),
      target('tendis_info_deleting_expire_keys', 'Deleting - {{instance}}', 'B')
    ],
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



  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
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
    targets: [
      target('tendis_info_rocksdb_size_all_mem_tables', 'Size All MemTables - {{instance}}', 'A'),
      target('tendis_info_rocksdb_cur_size_all_mem_tables', 'Cur Size All MemTables - {{instance}}', 'B')
    ],
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

  // Panel 43: CPU Breakdown
  g.panel.timeSeries.new('CPU Breakdown') + {
    description: 'Tendis CPU usage breakdown (sys/user/main/children)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_used_cpu_sys[5m])', 'Sys - {{instance}}', 'A'),
      target('rate(tendis_info_used_cpu_user[5m])', 'User - {{instance}}', 'B'),
      target('rate(tendis_info_used_cpu_sys_children[5m])', 'Sys Children - {{instance}}', 'C'),
      target('rate(tendis_info_used_cpu_user_children[5m])', 'User Children - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'mean', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 's' } }
  },

  // Panel 44: Process Threads
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
    description: 'Total connections received and released', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 8 },
    targets: [
      target('tendis_info_total_connections_received', 'Received - {{instance}}', 'A'),
      target('tendis_info_total_connections_released', 'Released - {{instance}}', 'B')
    ],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // Panel 52: Rejected Connections
  g.panel.stat.new('Rejected Connections') + {
    description: 'Rejected connections', datasource: 'Prometheus', gridPos: { h: 6, w: 8, x: 16 },
    targets: [target('tendis_info_rejected_connections', '{{instance}}')],
    options: { orientation: 'auto', reduceOptions: { values: false, calcs: ['lastNotNull'], fields: '' } },
    fieldConfig: { defaults: { color: { mode: 'thresholds' }, unit: 'short' } }
  },

  // BlobDB File I/O
  g.panel.timeSeries.new('BlobDB File I/O') + {
    description: 'Blob file bytes read, written and sync count', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_read_COUNT[5m])', 'File Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_bytes_written_COUNT[5m])', 'File Bytes Written - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_file_synced_COUNT[5m])', 'File Synced - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'bytes' } }
  },

  // BlobDB General Bytes
  g.panel.timeSeries.new('BlobDB General Bytes') + {
    description: 'BlobDB overall bytes read and written', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_bytes_read_COUNT[5m])', 'Bytes Read - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_bytes_written_COUNT[5m])', 'Bytes Written - {{instance}}', 'B')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'Bps' } }
  },

  // BlobDB Index Evict/Expire
  g.panel.timeSeries.new('BlobDB Index Evict/Expire') + {
    description: 'Blob index evicted and expired count and size', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_count_COUNT[5m])', 'Evicted Count - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_evicted_size_COUNT[5m])', 'Evicted Size - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_count_COUNT[5m])', 'Expired Count - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_blob_index_expired_size_COUNT[5m])', 'Expired Size - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB FIFO Eviction
  g.panel.timeSeries.new('BlobDB FIFO Eviction') + {
    description: 'BlobDB FIFO eviction stats', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_fifo_bytes_evicted_COUNT[5m])', 'Bytes Evicted - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_files_evicted_COUNT[5m])', 'Files Evicted - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_fifo_num_keys_evicted_COUNT[5m])', 'Keys Evicted - {{instance}}', 'C')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB GC
  g.panel.timeSeries.new('BlobDB GC') + {
    description: 'BlobDB garbage collection stats', datasource: 'Prometheus', gridPos: { h: 8, w: 24, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_gc_failures_COUNT[5m])', 'GC Failures - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_expired_COUNT[5m])', 'Bytes Expired - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_overwritten_COUNT[5m])', 'Bytes Overwritten - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_gc_bytes_relocated_COUNT[5m])', 'Bytes Relocated - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_files_COUNT[5m])', 'Num Files - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_new_files_COUNT[5m])', 'Num New Files - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_expired_COUNT[5m])', 'Keys Expired - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_overwritten_COUNT[5m])', 'Keys Overwritten - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_gc_num_keys_relocated_COUNT[5m])', 'Keys Relocated - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Operations
  g.panel.timeSeries.new('BlobDB Operations') + {
    description: 'BlobDB operation counts (get, put, seek, write, etc.)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 0 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_num_get_COUNT[5m])', 'Get - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_num_multiget_COUNT[5m])', 'MultiGet - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_num_put_COUNT[5m])', 'Put - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_num_write_COUNT[5m])', 'Write - {{instance}}', 'D'),
      target('rate(tendis_info_rocksdb_blobdb_num_seek_COUNT[5m])', 'Seek - {{instance}}', 'E'),
      target('rate(tendis_info_rocksdb_blobdb_num_next_COUNT[5m])', 'Next - {{instance}}', 'F'),
      target('rate(tendis_info_rocksdb_blobdb_num_prev_COUNT[5m])', 'Prev - {{instance}}', 'G'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_read_COUNT[5m])', 'Keys Read - {{instance}}', 'H'),
      target('rate(tendis_info_rocksdb_blobdb_num_keys_written_COUNT[5m])', 'Keys Written - {{instance}}', 'I')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
  },

  // BlobDB Write Types
  g.panel.timeSeries.new('BlobDB Write Types') + {
    description: 'BlobDB write classification (blob vs inlined, with/without TTL)', datasource: 'Prometheus', gridPos: { h: 8, w: 12, x: 12 },
    targets: [
      target('rate(tendis_info_rocksdb_blobdb_write_blob_COUNT[5m])', 'Write Blob - {{instance}}', 'A'),
      target('rate(tendis_info_rocksdb_blobdb_write_blob_ttl_COUNT[5m])', 'Write Blob TTL - {{instance}}', 'B'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_COUNT[5m])', 'Write Inlined - {{instance}}', 'C'),
      target('rate(tendis_info_rocksdb_blobdb_write_inlined_ttl_COUNT[5m])', 'Write Inlined TTL - {{instance}}', 'D')
    ],
    options: { legend: { displayMode: 'table', placement: 'bottom', calcs: ['last', 'max'] } },
    fieldConfig: { defaults: { color: { mode: 'palette-classic' }, unit: 'short' } }
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

