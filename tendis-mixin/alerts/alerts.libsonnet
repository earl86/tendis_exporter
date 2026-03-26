local config = import '../config.libsonnet';

{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'tendis_alerts',
        rules: [
          // 1. 实例宕机告警
          {
            alert: 'TendisInstanceDown',
            expr: 'tendis_exporter_up == 0',
            'for': '1m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Tendis instance is down',
              description: 'Tendis instance {{ $labels.instance }} has been down for more than 1 minute.',
            },
          },
          // 2. 集群状态异常
          {
            alert: 'TendisClusterStateDown',
            expr: 'tendis_cluster_state == 0',
            'for': '1m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Tendis cluster state is not OK',
              description: 'The cluster state reported by {{ $labels.instance }} is down/fail.',
            },
          },
          // 3. 内存使用率过高告警
          {
            alert: 'TendisHighMemoryUsage',
            expr: 'instance:tendis_memory_usage_ratio > %f' % config._config.alerts.memoryUsageCritical,
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Tendis memory usage is critically high',
              description: 'Tendis instance {{ $labels.instance }} memory usage is above %d%%.' % (config._config.alerts.memoryUsageCritical * 100),
            },
          },
          // 4. 主从同步延迟告警
          {
            alert: 'TendisReplicationLagHigh',
            expr: 'tendis_slave_lag_seconds > %d' % config._config.alerts.slaveLagSecondsCritical,
            'for': '3m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis replication lag is high',
              description: 'Slave {{ $labels.slave_id }} on {{ $labels.instance }} is lagging by {{ $value }} seconds.',
            },
          },
          // 5. 主从复制偏移延迟告警
          {
            alert: 'TendisReplicationOffsetLagHigh',
            expr: 'instance:tendis_replication_offset_lag > 10000',
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis replication offset lag is high',
              description: 'Master {{ $labels.instance }} replication offset lag is {{ $value }}.',
            },
          },
          // 6. Binlog 堆积告警
          {
            alert: 'TendisBinlogRemainHigh',
            expr: 'instance:tendis_binlog_remain_total > %d' % config._config.alerts.binlogRemainCritical,
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis Binlog accumulation is too high',
              description: 'Instance {{ $labels.instance }} has {{ $value }} unconsumed binlogs, indicating potential sync or IO issues.',
            },
          },
          // 7. Compaction 停止告警
          {
            alert: 'TendisCompactionStopped',
            expr: 'tendis_compaction_status{status="stopped"} == 1',
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis RocksDB Compaction has stopped',
              description: 'RocksDB compaction on {{ $labels.instance }} has been stopped for 10 minutes, disk space may inflate rapidly.',
            },
          },
          // 8. RocksDB 读取延迟过高
          {
            alert: 'TendisRocksDBHighReadLatency',
            expr: 'instance:tendis_avg_command_latency_seconds > %f' % config._config.alerts.rocksdbReadLatencyCritical,
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis command latency is high',
              description: 'Average command latency on {{ $labels.instance }} is {{ $value }}s.',
            },
          },
          // 9. 进程内存使用过高 (优化：预计算字节数，使用 humanize1024)
          {
            alert: 'TendisProcessHighMemoryUsage',
            expr: 'tendis_tendis_process_resident_memory_bytes > %d' % (config._config.alerts.processMemoryUsageCriticalGB * 1024 * 1024 * 1024),
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis process memory usage is high',
              description: 'Tendis process on {{ $labels.instance }} is using {{ $value | humanize1024 }} (> %dGiB).' % config._config.alerts.processMemoryUsageCriticalGB,
            },
          },
          // 10. 主从 Binlog 延迟过高
          {
            alert: 'TendisSlaveBinlogLagHigh',
            expr: 'tendis_slave_binlog_lag_seconds > %d' % config._config.alerts.slaveBinlogLagCritical,
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis slave binlog lag is high',
              description: 'Slave {{ $labels.slave_id }} on {{ $labels.instance }} binlog lag is {{ $value }}s (> %ds).' % config._config.alerts.slaveBinlogLagCritical,
            },
          },
          // 11. 块缓存命中率过低
          {
            alert: 'TendisLowBlockCacheHitRate',
            expr: 'instance:tendis_block_cache_hit_rate < %f' % config._config.alerts.cacheHitRateWarning,
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis block cache hit rate is low',
              description: 'Block cache hit rate on {{ $labels.instance }} is {{ $value }}%% (< %d%%).' % (config._config.alerts.cacheHitRateWarning * 100),
            },
          },
          // 12. 键空间命中率过低
          {
            alert: 'TendisLowKeyspaceHitRate',
            expr: 'instance:tendis_keyspace_hit_rate < 0.80',
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis keyspace hit rate is low',
              description: 'Keyspace hit rate on {{ $labels.instance }} is {{ $value }}%% (< 80%%).',
            },
          },
          // 13. 连接数过高
          {
            alert: 'TendisHighConnections',
            expr: 'tendis_info_connected_clients > %d' % config._config.alerts.connectionWarningThreshold,
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis connections are high',
              description: 'Instance {{ $labels.instance }} has {{ $value }} connected clients (> %d).' % config._config.alerts.connectionWarningThreshold,
            },
          },
          // 14. QPS 过高
          {
            alert: 'TendisHighQPS',
            expr: 'instance:tendis_commands_qps:rate5m > %d' % config._config.alerts.qpsWarningThreshold,
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis QPS is high',
              description: 'Instance {{ $labels.instance }} QPS is {{ $value }} (> %d).' % config._config.alerts.qpsWarningThreshold,
            },
          },
          // 15. 磁盘 I/O 过高 (优化：预计算字节数，使用 humanize1024)
          {
            alert: 'TendisHighDiskIO',
            expr: 'instance:tendis_disk_read_physical_bps + instance:tendis_disk_write_physical_bps > %d' % (config._config.alerts.diskIOWarningMbps * 1024 * 1024),
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis disk I/O is high',
              description: 'Instance {{ $labels.instance }} disk I/O is {{ $value | humanize1024 }}ps (> %dMiB/s).' % config._config.alerts.diskIOWarningMbps,
            },
          },
          // 16. 从库状态离线
          {
            alert: 'TendisSlaveOffline',
            expr: 'tendis_slave_state == 0',
            'for': '2m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Tendis slave is offline',
              description: 'Slave {{ $labels.slave_id }} on {{ $labels.instance }} is offline.',
            },
          },
          // 17. RocksDB 压积字节数过高 (优化：使用普通乘法展开和 humanize1024)
          {
            alert: 'TendisHighPendingCompaction',
            expr: 'tendis_info_rocksdb_estimate_pending_compaction_bytes > 10 * 1024 * 1024 * 1024',
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis pending compaction is high',
              description: 'Instance {{ $labels.instance }} has {{ $value | humanize1024 }} pending compaction bytes (> 10GiB).',
            },
          },
          // 18. 拒绝连接数增长
          {
            alert: 'TendisConnectionRejected',
            expr: 'rate(tendis_info_rejected_connections[5m]) > 10',
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis connections are being rejected',
              description: 'Instance {{ $labels.instance }} is rejecting connections at {{ $value }}/sec.',
            },
          },
          // 19. CPU 使用率过高
          {
            alert: 'TendisHighCPUUsage',
            expr: 'instance:tendis_cpu_usage_percent > 80',
            'for': '10m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis CPU usage is high',
              description: 'Instance {{ $labels.instance }} CPU usage is {{ $value }}%% (> 80%%).',
            },
          },
          // 20. 集群槽位分布异常
          {
            alert: 'TendisClusterSlotFail',
            expr: 'tendis_info_cluster_cluster_slots_fail > 0',
            'for': '5m',
            labels: { severity: 'critical' },
            annotations: {
              summary: 'Tendis cluster has failed slots',
              description: 'Instance {{ $labels.instance }} has {{ $value }} failed slots.',
            },
          },
          // 21. 集群槽位部分失败
          {
            alert: 'TendisClusterSlotPFail',
            expr: 'tendis_info_cluster_cluster_slots_pfail > 0',
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis cluster has potentially failed slots',
              description: 'Instance {{ $labels.instance }} has {{ $value }} potentially failed slots.',
            },
          },
          // 22. 平均 TTL 过短（可能影响性能）
          {
            alert: 'TendisShortAverageTTL',
            expr: 'avg by(instance) (tendis_db_avg_ttl_seconds) < 60 and avg by(instance) (tendis_db_avg_ttl_seconds) > 0',
            'for': '10m',
            labels: { severity: 'info' },
            annotations: {
              summary: 'Tendis average TTL is short',
              description: 'Instance {{ $labels.instance }} average TTL is {{ $value }}s, which may cause performance issues.',
            },
          },
          // 23. 主库最后 I/O 时间过长
          {
            alert: 'TendisMasterLastIODelay',
            expr: 'tendis_info_master_last_io_seconds_ago > 60',
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis master last I/O is delayed',
              description: 'Master {{ $labels.instance }} last I/O was {{ $value }}s ago (> 60s).',
            },
          },
          // 24. RocksDB SST 文件大小增长过快 (优化：使用普通乘法展开和 humanize1024)
          {
            alert: 'TendisHighSSTFileSize',
            expr: 'tendis_info_rocksdb_total_sst_files_size > 100 * 1024 * 1024 * 1024',
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis SST files are large',
              description: 'Instance {{ $labels.instance }} SST files size is {{ $value | humanize1024 }} (> 100GiB).',
            },
          },
          // 25. 网络带宽使用过高 (优化：预计算展开)
          {
            alert: 'TendisHighNetworkBandwidth',
            expr: 'instance:tendis_net_input_bps + instance:tendis_net_output_bps > 1000 * 1024 * 1024',
            'for': '5m',
            labels: { severity: 'warning' },
            annotations: {
              summary: 'Tendis network bandwidth is high',
              description: 'Instance {{ $labels.instance }} network bandwidth is {{ $value | humanize }}bps (> 1Gbps).',
            },
          },
        ],
      },
    ],
  },
}
