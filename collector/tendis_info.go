package collector

import (
	"context"
	"log/slog"
	"regexp"
	"strconv"
	"strings"

	"github.com/prometheus/client_golang/prometheus"
)

// ==============================================================================
// 1. 常量与配置
// ==============================================================================
const (
	tendisNamespace = "tendis"
	tendisSubsystem = "info"
)

// 需要强制置为 0 的 Key 列表
var sanitizeZeroKeys = map[string]bool{
	"mem_fragmentation_bytes":      true,
	"rdb_current_bgsave_time_sec":  true,
	"aof_last_rewrite_time_sec":    true,
	"aof_current_rewrite_time_sec": true,
	"second_repl_offset":           true,
}

// ==============================================================================
// 2. 静态 Descriptors
// ==============================================================================
var (
	// --- Command Stats ---
	cmdCallsDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "command", "calls_total"),
		"Total number of calls for a specific command",
		[]string{"cmd"}, nil,
	)
	cmdUsecDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "command", "usec_total"),
		"Total CPU time consumed by command in microseconds",
		[]string{"cmd"}, nil,
	)
	cmdUsecPerCallDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "command", "usec_per_call"),
		"Average CPU time consumed per call in microseconds",
		[]string{"cmd"}, nil,
	)

	// --- Keyspace ---
	dbKeysDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "db", "keys"),
		"Total number of keys in the database",
		[]string{"db"}, nil,
	)
	dbExpiresDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "db", "expires"),
		"Total number of expiring keys in the database",
		[]string{"db"}, nil,
	)
	dbAvgTtlDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "db", "avg_ttl_seconds"),
		"Average TTL of keys in the database",
		[]string{"db"}, nil,
	)

	// --- Error Stats ---
	errorStatDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "error", "count_total"),
		"Total number of errors by type",
		[]string{"error_type"}, nil,
	)

	// --- Role ---
	roleMasterDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "replication", "is_master"),
		"1 if the instance is master, 0 otherwise",
		nil, nil,
	)

	// --- Slave Stats ---
	slaveStateDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "slave", "state"),
		"1 if online, 0 otherwise",
		[]string{"slave_id"}, nil,
	)
	slaveOffsetDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "slave", "offset"),
		"Replication offset",
		[]string{"slave_id"}, nil,
	)
	slaveLagDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "slave", "lag_seconds"),
		"Replication lag",
		[]string{"slave_id"}, nil,
	)
	slaveBinlogLagDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "slave", "binlog_lag_seconds"),
		"Replication binlog lag",
		[]string{"slave_id"}, nil,
	)

	// --- Slowlog ---
	slowLogIdDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "slowlog", "last_id"),
		"ID of the last slowlog entry",
		nil, nil,
	)

	// --- Cluster Info ---
	clusterStateDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "cluster", "state"),
		"1 if cluster is ok, 0 otherwise",
		nil, nil,
	)

	// ⬇️⬇️⬇️ 新增: BinlogInfo ---
	binlogMinDesc    = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "binlog", "min"), "Binlog min sequence", []string{"db"}, nil)
	binlogSaveDesc   = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "binlog", "save"), "Binlog save sequence", []string{"db"}, nil)
	binlogBLWMDesc   = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "binlog", "BLWM"), "Binlog low water mark", []string{"db"}, nil)
	binlogBHWMDesc   = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "binlog", "BHWM"), "Binlog high water mark", []string{"db"}, nil)
	binlogRemainDesc = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "binlog", "remain"), "Binlog remain count", []string{"db"}, nil)

	// ⬇️⬇️⬇️ 新增: Levelstats ---
	levelstatsBytesDesc          = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "levelstats", "bytes"), "Levelstats bytes", []string{"db", "level"}, nil)
	levelstatsEntriesDesc        = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "levelstats", "num_entries"), "Levelstats number of entries", []string{"db", "level"}, nil)
	levelstatsDeletionsDesc      = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "levelstats", "num_deletions"), "Levelstats number of deletions", []string{"db", "level"}, nil)
	levelstatsRangeDeletionsDesc = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "levelstats", "num_range_deletions"), "Levelstats number of range deletions", []string{"db", "level"}, nil)
	levelstatsFilesDesc          = prometheus.NewDesc(prometheus.BuildFQName(tendisNamespace, "levelstats", "num_files"), "Levelstats number of files", []string{"db", "level"}, nil)

	// ⬇️⬇️⬇️ 新增: 状态类型的 Label 指标 ⬇️⬇️⬇️
	compactionStatusDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "compaction", "status"),
		"Current compaction status",
		[]string{"status"}, nil,
	)

	backupRunningDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "backup", "running"),
		"Current backup running status",
		[]string{"status"}, nil,
	)

	roleDesc = prometheus.NewDesc(
		prometheus.BuildFQName(tendisNamespace, "replication", "role"),
		"Current role of the instance",
		[]string{"role"}, nil,
	)
)

// ==============================================================================
// 3. Scraper 定义
// ==============================================================================
type ScrapeTendisInfo struct{}

func (ScrapeTendisInfo) Name() string { return "tendis_info" }
func (ScrapeTendisInfo) Help() string {
	return "Collects Tendis INFO, SLOWLOG, CLUSTER INFO and RocksDB stats"
}
func (ScrapeTendisInfo) Version() float64 { return 0 }

// ==============================================================================
// 4. 核心逻辑 (Scrape)
// ==============================================================================
func (s ScrapeTendisInfo) Scrape(ctx context.Context, instance *TendisInstance, ch chan<- prometheus.Metric, logger *slog.Logger) error {
	rawInfo, err := instance.Client.Info(ctx, "all").Result()
	if err != nil {
		logger.Error("Failed to execute INFO ALL", "err", err)
		return err
	}
	infoMap := parseInfoToMap(rawInfo)

	// 提取版本号: "2.6.0-rocksdb-v6.23.3" -> 2.6
	tendisVersion := 0.0
	if vStr, ok := infoMap["tendis_version"]; ok {
		tendisVersion = parseTendisVersion(vStr)
	} else if vStr, ok := infoMap["redis_version"]; ok {
		tendisVersion = parseTendisVersion(vStr)
	}

	for key, valStr := range infoMap {
		// --- A. 归零处理 ---
		if sanitizeZeroKeys[key] {
			val := parseSafeFloat(valStr)
			if val < 0 {
				val = 0
			}
			emitDynamicMetric(ch, key, val)
			continue
		}

		// --- B. Command Stats ---
		if strings.HasPrefix(key, "cmdstat_") && key != "cmdstat_unseen" {
			cmdName := strings.TrimPrefix(key, "cmdstat_")
			inner := parseInnerMap(valStr)
			emitIfPresent(ch, inner, "calls", cmdCallsDesc, cmdName)
			emitIfPresent(ch, inner, "usec", cmdUsecDesc, cmdName)
			emitIfPresent(ch, inner, "usec_per_call", cmdUsecPerCallDesc, cmdName)
			continue
		}

		// --- C. cmdstat_unseen ---
		if key == "cmdstat_unseen" {
			inner := parseInnerMap(valStr)
			emitIfPresent(ch, inner, "calls", cmdCallsDesc, "unseen")
			if v, ok := inner["num"]; ok {
				emitDynamicMetric(ch, "cmdstat_unseen_num", parseSafeFloat(v))
			}
			continue
		}

		// --- D. Keyspace ---
		if strings.HasPrefix(key, "db") && isDbKey(key) {
			dbName := key
			inner := parseInnerMap(valStr)
			emitIfPresent(ch, inner, "keys", dbKeysDesc, dbName)
			emitIfPresent(ch, inner, "expires", dbExpiresDesc, dbName)
			emitIfPresent(ch, inner, "avg_ttl", dbAvgTtlDesc, dbName)
			continue
		}

		// --- E. Error Stats ---
		if strings.HasPrefix(key, "errorstat_") {
			errType := strings.TrimPrefix(key, "errorstat_")
			inner := parseInnerMap(valStr)
			emitIfPresent(ch, inner, "count", errorStatDesc, errType)
			continue
		}

		// --- F. Slave Stats ---
		if strings.HasPrefix(key, "slave") && isDigit(strings.TrimPrefix(key, "slave")) {
			slaveID := key
			inner := parseInnerMap(valStr)
			if state, ok := inner["state"]; ok {
				val := 0.0
				if state == "online" {
					val = 1.0
				}
				ch <- prometheus.MustNewConstMetric(slaveStateDesc, prometheus.GaugeValue, val, slaveID)
			}
			emitIfPresent(ch, inner, "offset", slaveOffsetDesc, slaveID)
			emitIfPresent(ch, inner, "lag", slaveLagDesc, slaveID)
			emitIfPresent(ch, inner, "binlog_lag", slaveBinlogLagDesc, slaveID)
			continue
		}

		// ⬇️⬇️⬇️ 新增: 字符串状态转 Label 展现 ⬇️⬇️⬇️
		if key == "current-compaction-status" {
			ch <- prometheus.MustNewConstMetric(compactionStatusDesc, prometheus.GaugeValue, 1.0, valStr)
			continue
		}
		if key == "current-backup-running" {
			ch <- prometheus.MustNewConstMetric(backupRunningDesc, prometheus.GaugeValue, 1.0, valStr)
			continue
		}

		// --- G. Role (增加 Label 展现，并保留之前的兼容) ---
		if key == "role" {
			// 1. 新的方式：作为 Label 展示
			ch <- prometheus.MustNewConstMetric(roleDesc, prometheus.GaugeValue, 1.0, valStr)

			// 2. 老的方式：向下兼容原有的 is_master (1 或 0)
			val := 0.0
			if valStr == "master" {
				val = 1.0
			}
			ch <- prometheus.MustNewConstMetric(roleMasterDesc, prometheus.GaugeValue, val)
			continue
		}

		// --- H. 特殊矩阵 ---
		if key == "scanner_matrix" || key == "deleter_matrix" {
			parts := strings.Split(valStr, ",")
			for _, part := range parts {
				part = strings.TrimSpace(part)
				kv := strings.Fields(part)
				if len(kv) != 2 {
					kv = strings.Split(part, ":")
				}
				if len(kv) == 2 {
					subKey := kv[0]
					subValStr := strings.TrimSuffix(kv[1], "ns")
					fullKey := key + "_" + subKey
					emitDynamicMetric(ch, fullKey, parseSafeFloat(subValStr))
				}
			}
			continue
		}

		// --- I. scanpoint ---
		if strings.HasPrefix(key, "scanpoint") {
			emitDynamicMetric(ch, "index_"+key, parseSafeFloat(valStr))
			continue
		}

		// ⬇️⬇️⬇️ 新增: L. Levelstats (如 rocksdb0.level-0) ⬇️⬇️⬇️
		if strings.HasPrefix(key, "rocksdb") && strings.Contains(key, ".level-") {
			parts := strings.SplitN(key, ".", 2)
			if len(parts) == 2 {
				dbName := parts[0]    // rocksdb0
				levelName := parts[1] // level-0
				inner := parseInnerMap(valStr)

				emitIfPresent(ch, inner, "bytes", levelstatsBytesDesc, dbName, levelName)
				emitIfPresent(ch, inner, "num_entries", levelstatsEntriesDesc, dbName, levelName)
				emitIfPresent(ch, inner, "num_deletions", levelstatsDeletionsDesc, dbName, levelName)
				emitIfPresent(ch, inner, "num_range_deletions", levelstatsRangeDeletionsDesc, dbName, levelName)
				emitIfPresent(ch, inner, "num_files", levelstatsFilesDesc, dbName, levelName)
			}
			continue
		}

		// ⬇️⬇️⬇️ 新增: M. BinlogInfo (如 rocksdb0, rocksdb1) ⬇️⬇️⬇️
		if strings.HasPrefix(key, "rocksdb") && !strings.Contains(key, ".") {
			dbName := key // rocksdb0
			inner := parseInnerMap(valStr)
			// 简单验证是否包含 binlog 相关的字段，防止误杀其他格式的 rocksdbX 指标
			if _, ok := inner["remain"]; ok {
				emitIfPresent(ch, inner, "min", binlogMinDesc, dbName)
				emitIfPresent(ch, inner, "save", binlogSaveDesc, dbName)
				emitIfPresent(ch, inner, "BLWM", binlogBLWMDesc, dbName)
				emitIfPresent(ch, inner, "BHWM", binlogBHWMDesc, dbName)
				emitIfPresent(ch, inner, "remain", binlogRemainDesc, dbName)
				continue
			}
		}

		// --- J. global rocksdb.* ---
		if strings.HasPrefix(key, "rocksdb.") {
			cleanKey := key
			if strings.HasSuffix(key, " COUNT ") {
				cleanKey = strings.Replace(key, " COUNT ", ".COUNT", 1)
			}
			cleanKey = strings.TrimSpace(cleanKey)
			emitDynamicMetric(ch, cleanKey, parseSafeFloat(valStr))
			continue
		}

		// --- K. 兜底 ---
		if val, err := strconv.ParseFloat(valStr, 64); err == nil {
			emitDynamicMetric(ch, key, val)
		}
	}

	// ========================================================================
	// Phase 2: SLOWLOG GET 1
	// ========================================================================
	slowlogs, err := instance.Client.SlowLogGet(ctx, 1).Result()
	if err == nil && len(slowlogs) > 0 {
		ch <- prometheus.MustNewConstMetric(slowLogIdDesc, prometheus.CounterValue, float64(slowlogs[0].ID))
	} else if err != nil && err.Error() != "ERR unknown command 'SLOWLOG'" {
		// 忽略未知命令的报错，防止有些裁剪版的 Tendis 没这命令
		logger.Warn("Failed to get SLOWLOG", "err", err)
	}

	// ========================================================================
	// Phase 3: CLUSTER INFO
	// ========================================================================
	clusterInfoStr, err := instance.Client.ClusterInfo(ctx).Result()
	if err == nil {
		clusterLines := strings.Split(clusterInfoStr, "\r\n")
		for _, line := range clusterLines {
			if strings.Contains(line, ":") {
				parts := strings.SplitN(line, ":", 2)
				key := parts[0]
				valStr := strings.TrimSpace(parts[1])

				if key == "cluster_state" {
					val := 0.0
					if valStr == "ok" {
						val = 1.0
					}
					ch <- prometheus.MustNewConstMetric(clusterStateDesc, prometheus.GaugeValue, val)
				} else {
					if val, err := strconv.ParseFloat(valStr, 64); err == nil {
						emitDynamicMetric(ch, "cluster_"+key, val)
					}
				}
			}
		}
	}

	// ========================================================================
	// Phase 4: INFO rocksdbstats (Only for version <= 2.6)
	// ========================================================================
	if tendisVersion > 0 && tendisVersion <= 2.6 {
		val, err := instance.Client.Do(ctx, "info", "rocksdbstats").Result()
		if err == nil {
			var rawStats string
			switch v := val.(type) {
			case string:
				rawStats = v
			case []byte:
				rawStats = string(v)
			}

			lines := strings.Split(rawStats, "\r\n")
			for _, line := range lines {
				if strings.HasPrefix(line, "rocksdb.") {
					line = strings.TrimSpace(line)
					line = strings.Replace(line, " COUNT ", ".COUNT", -1)

					parts := strings.Split(line, ":")
					if len(parts) >= 2 {
						key := parts[0]
						valStr := strings.TrimSpace(parts[1])
						emitDynamicMetric(ch, key, parseSafeFloat(valStr))
					}
				}
			}
		}
	}

	return nil
}

// ==============================================================================
// 5. 辅助工具函数
// ==============================================================================

func emitDynamicMetric(ch chan<- prometheus.Metric, key string, val float64) {
	sanitizedKey := sanitizeMetricName(key)
	metricName := prometheus.BuildFQName(tendisNamespace, tendisSubsystem, sanitizedKey)

	valType := prometheus.GaugeValue
	if strings.HasSuffix(key, "_total") || strings.HasPrefix(key, "total_") || strings.Contains(key, "calls") {
		valType = prometheus.CounterValue
	}

	desc := prometheus.NewDesc(metricName, "Auto generated metric from Tendis", nil, nil)
	ch <- prometheus.MustNewConstMetric(desc, valType, val)
}

// ⚠️ 注意：修改了此方法，增加了 ...string，以支持动态数量的 Label (例如 db 和 level)
func emitIfPresent(ch chan<- prometheus.Metric, m map[string]string, key string, desc *prometheus.Desc, labelVals ...string) {
	if valStr, ok := m[key]; ok {
		if val, err := strconv.ParseFloat(valStr, 64); err == nil {
			vType := prometheus.GaugeValue
			if strings.Contains(desc.String(), "calls") || strings.Contains(desc.String(), "usec") {
				vType = prometheus.CounterValue
			}
			ch <- prometheus.MustNewConstMetric(desc, vType, val, labelVals...)
		}
	}
}

func parseInfoToMap(raw string) map[string]string {
	res := make(map[string]string)
	lines := strings.Split(raw, "\r\n")
	for _, line := range lines {
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			res[parts[0]] = strings.TrimSpace(parts[1])
		}
	}
	return res
}

func parseInnerMap(raw string) map[string]string {
	res := make(map[string]string)
	pairs := strings.Split(raw, ",")
	for _, pair := range pairs {
		kv := strings.SplitN(pair, "=", 2)
		if len(kv) == 2 {
			res[kv[0]] = kv[1]
		}
	}
	return res
}

func parseSafeFloat(s string) float64 {
	v, _ := strconv.ParseFloat(s, 64)
	return v
}

func isDbKey(s string) bool {
	return len(s) > 2 && isDigit(s[2:])
}

func isDigit(s string) bool {
	if len(s) == 0 {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// parseTendisVersion: "2.6.0-rocksdb-v6.23.3" -> 2.6
func parseTendisVersion(vStr string) float64 {
	re := regexp.MustCompile(`^(\d+\.\d+)`)
	matches := re.FindStringSubmatch(vStr)
	if len(matches) >= 2 {
		if val, err := strconv.ParseFloat(matches[1], 64); err == nil {
			return val
		}
	}
	return 0.0
}

func sanitizeMetricName(s string) string {
	// 1. 将连续的非字母数字字符替换为单个下划线
	// 比如 "cost(ns)" -> "cost_ns_"
	reg := regexp.MustCompile(`[^a-zA-Z0-9_]+`)
	sanitized := reg.ReplaceAllString(s, "_")

	// 2. 去除开头和结尾多余的下划线
	// "cost_ns_" -> "cost_ns"
	return strings.Trim(sanitized, "_")
}
