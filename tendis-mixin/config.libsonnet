{
  _config+:: {
    // 告警阈值配置
    alerts: {
      memoryUsageCritical: 0.90,       // 内存使用率大于 90%
      slaveLagSecondsCritical: 30,     // 主从延迟大于 30 秒
      binlogRemainCritical: 5000000,   // Binlog 堆积超过 500 万
      compactionStatusWarning: true,   // 是否对 compaction 异常进行告警
      rocksdbReadLatencyCritical: 0.1,  // RocksDB 读取延迟大于 100ms
      rocksdbWriteLatencyCritical: 0.1, // RocksDB 写入延迟大于 100ms
      processMemoryUsageCriticalGB: 10, // 进程内存使用大于 10GB
      slaveBinlogLagCritical: 60,       // 从库 binlog 延迟大于 60 秒
      cacheHitRateWarning: 0.5,       // 缓存命中率低于 50%
      diskIOWarningMbps: 100,          // 磁盘 I/O 超过 100MB/s
      qpsWarningThreshold: 10000,      // QPS 警告阈值
      connectionWarningThreshold: 10000, // 连接数警告阈值
    },
  },

  _dashboard+:: {
    title: 'Tendis Overview',
    uid: 'tendis-overview',
    tags: ['tendis', 'redis', 'rocksdb', 'database'],
    timeFrom: 'now-1h',
    refresh: '30s',
  },
}
