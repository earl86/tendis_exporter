local config = import '../config.libsonnet';

{
  prometheusRules+:: {
    groups+: [
      {
        name: 'tendis_recording_rules',
        rules: [
          // 预计算实例总 QPS (5分钟级别)
          {
            record: 'instance:tendis_commands_qps:rate5m',
            expr: 'sum by (instance) (rate(tendis_info_total_commands_processed[5m]))',
          },
          // 预计算瞬时 QPS
          {
            record: 'instance:tendis_instant_qps',
            expr: 'sum by (instance) (tendis_info_instantaneous_ops_per_sec)',
          },
          // 预计算内存使用率
          {
            record: 'instance:tendis_memory_usage_ratio',
            expr: 'tendis_info_used_memory / tendis_info_maxmemory',
          },
          // 预计算键空间命中率
          {
            record: 'instance:tendis_keyspace_hit_rate',
            expr: 'rate(tendis_info_keyspace_hits[5m]) / (rate(tendis_info_keyspace_hits[5m]) + rate(tendis_info_keyspace_misses[5m])) * 100',
          },
          // 预计算平均命令延迟
          {
            record: 'instance:tendis_avg_command_latency_seconds',
            expr: 'rate(tendis_info_total_commands_cost_ns[5m]) / rate(tendis_info_total_commands_processed[5m]) / 1e9',
          },
          // 预计算所有 RocksDB Level 文件总数
          {
            record: 'instance_db:tendis_levelstats_files:sum',
            expr: 'sum by(instance, db) (tendis_levelstats_num_files)',
          },
          // 预计算所有 RocksDB Level Bytes 总数
          {
            record: 'instance_db:tendis_levelstats_bytes:sum',
            expr: 'sum by(instance, db) (tendis_levelstats_bytes)',
          },
          // 预计算 RocksDB Level 文件数（按层级）
          {
            record: 'instance_level:tendis_levelstats_num_files:sum',
            expr: 'sum by(instance, level) (tendis_levelstats_num_files)',
          },
          // 预计算 RocksDB Level 字节数（按层级）
          {
            record: 'instance_level:tendis_levelstats_bytes:sum',
            expr: 'sum by(instance, level) (tendis_levelstats_bytes)',
          },
          // 预计算 RocksDB Level 条目数（按层级）
          {
            record: 'instance_level:tendis_levelstats_entries:sum',
            expr: 'sum by(instance, level) (tendis_levelstats_num_entries)',
          },
          // 预计算所有 DB 的总键数
          {
            record: 'instance:tendis_total_keys',
            expr: 'sum by(instance) (tendis_db_keys)',
          },
          // 预计算所有 DB 的过期键数
          {
            record: 'instance:tendis_total_expires',
            expr: 'sum by(instance) (tendis_db_expires)',
          },
          // 预计算从库复制偏移量
          {
            record: 'instance:tendis_slave_offset',
            expr: 'tendis_slave_offset',
          },
          // 预计算主库复制延迟（偏移量差值）
          {
            record: 'instance:tendis_replication_offset_lag',
            expr: 'tendis_info_master_repl_offset - max by(instance) (tendis_slave_offset)',
          },
          // 预计算网络输入速率 (bits/sec)
          {
            record: 'instance:tendis_net_input_bps',
            expr: 'rate(tendis_info_total_net_input_bytes[5m]) * 8',
          },
          // 预计算网络输出速率 (bits/sec)
          {
            record: 'instance:tendis_net_output_bps',
            expr: 'rate(tendis_info_total_net_output_bytes[5m]) * 8',
          },
          // 预计算块缓存命中率
          {
            record: 'instance:tendis_block_cache_hit_rate',
            expr: 'rate(tendis_info_rocksdb_block_cache_hit_COUNT[5m]) / (rate(tendis_info_rocksdb_block_cache_hit_COUNT[5m]) + rate(tendis_info_rocksdb_block_cache_miss_COUNT[5m])) * 100',
          },
          // 预计算索引缓存命中率
          {
            record: 'instance:tendis_block_cache_index_hit_rate',
            expr: 'rate(tendis_info_rocksdb_block_cache_index_hit_COUNT[5m]) / (rate(tendis_info_rocksdb_block_cache_index_hit_COUNT[5m]) + rate(tendis_info_rocksdb_block_cache_index_miss_COUNT[5m])) * 100',
          },
          // 预计算 Bloom 过滤器有效性
          {
            record: 'instance:tendis_bloom_filter_effectiveness',
            expr: 'rate(tendis_info_rocksdb_bloom_filter_useful_COUNT[5m]) / (rate(tendis_info_rocksdb_bloom_filter_useful_COUNT[5m]) + rate(tendis_info_rocksdb_bloom_filter_full_positive_COUNT[5m])) * 100',
          },
          // 预计算 RocksDB 读取速率
          {
            record: 'instance:tendis_rocksdb_read_bps',
            expr: 'rate(tendis_info_rocksdb_bytes_read_COUNT[5m])',
          },
          // 预计算 RocksDB 写入速率
          {
            record: 'instance:tendis_rocksdb_write_bps',
            expr: 'rate(tendis_info_rocksdb_bytes_written_COUNT[5m])',
          },
          // 预计算 RocksDB 压缩读取速率
          {
            record: 'instance:tendis_rocksdb_compact_read_bps',
            expr: 'rate(tendis_info_rocksdb_compact_read_bytes_COUNT[5m])',
          },
          // 预计算 RocksDB 压缩写入速率
          {
            record: 'instance:tendis_rocksdb_compact_write_bps',
            expr: 'rate(tendis_info_rocksdb_compact_write_bytes_COUNT[5m])',
          },
          // 预计算过期键速率
          {
            record: 'instance:tendis_expire_keys_rate',
            expr: 'rate(tendis_info_total_expire_keys[5m])',
          },
          // 预计算 CPU 使用率
          {
            record: 'instance:tendis_cpu_usage_percent',
            expr: 'rate(tendis_tendis_process_cpu_seconds_total[5m]) * 100',
          },
          // 预计算上下文切换速率（自愿）
          {
            record: 'instance:tendis_context_switches_voluntary_rate',
            expr: 'rate(tendis_tendis_process_context_switches_voluntary_total[5m])',
          },
          // 预计算上下文切换速率（非自愿）
          {
            record: 'instance:tendis_context_switches_nonvoluntary_rate',
            expr: 'rate(tendis_tendis_process_context_switches_nonvoluntary_total[5m])',
          },
          // 预计算缺页速率（次要）
          {
            record: 'instance:tendis_page_faults_minor_rate',
            expr: 'rate(tendis_tendis_process_page_faults_minor_total[5m])',
          },
          // 预计算缺页速率（主要）
          {
            record: 'instance:tendis_page_faults_major_rate',
            expr: 'rate(tendis_tendis_process_page_faults_major_total[5m])',
          },
          // 预计算磁盘读取速率（物理）
          {
            record: 'instance:tendis_disk_read_physical_bps',
            expr: 'rate(tendis_tendis_process_io_read_bytes_total[5m])',
          },
          // 预计算磁盘读取速率（逻辑）
          {
            record: 'instance:tendis_disk_read_logical_bps',
            expr: 'rate(tendis_tendis_process_io_rchar_bytes_total[5m])',
          },
          // 预计算磁盘写入速率（物理）
          {
            record: 'instance:tendis_disk_write_physical_bps',
            expr: 'rate(tendis_tendis_process_io_write_bytes_total[5m])',
          },
          // 预计算磁盘写入速率（逻辑）
          {
            record: 'instance:tendis_disk_write_logical_bps',
            expr: 'rate(tendis_tendis_process_io_wchar_bytes_total[5m])',
          },
          // 预计算 I/O 读取操作速率
          {
            record: 'instance:tendis_io_read_ops_rate',
            expr: 'rate(tendis_tendis_process_io_syscr_total[5m])',
          },
          // 预计算 I/O 写入操作速率
          {
            record: 'instance:tendis_io_write_ops_rate',
            expr: 'rate(tendis_tendis_process_io_syscw_total[5m])',
          },
          // 预计算块 I/O 延迟速率
          {
            record: 'instance:tendis_blkio_delay_rate',
            expr: 'rate(tendis_tendis_process_blkio_delay_seconds_total[5m])',
          },
          // 预计算 Binlog 剩余总数
          {
            record: 'instance:tendis_binlog_remain_total',
            expr: 'sum by(instance) (tendis_binlog_remain)',
          },
          // 预计算 Binlog 高水位
          {
            record: 'instance:tendis_binlog_bhwm',
            expr: 'sum by(instance) (tendis_binlog_BHWM)',
          },
          // 预计算 Binlog 低水位
          {
            record: 'instance:tendis_binlog_blwm',
            expr: 'sum by(instance) (tendis_binlog_BLWM)',
          },
          // 预计算命令调用速率（按命令）
          {
            record: 'cmd_instance:tendis_command_calls_rate',
            expr: 'sum by(cmd, instance) (rate(tendis_command_calls_total[5m]))',
          },
          // 预计算命令平均延迟
          {
            record: 'cmd_instance:tendis_command_avg_latency',
            expr: 'avg by(cmd, instance) (tendis_command_usec_per_call)',
          },
        ],
      },
    ],
  },
}
