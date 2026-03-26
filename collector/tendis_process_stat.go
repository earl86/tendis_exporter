package collector

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"sync"

	"github.com/prometheus/client_golang/prometheus"
)

// ==============================================================================
// 1. 定义常量
// ==============================================================================
const (
	// 指标子系统名称，最终指标将显示为 tendis_tendis_process_xxx
	tendisProcess = "tendis_process"
	linuxUserHz   = 100.0
)

// ==============================================================================
// 2. Metrics Descriptors (全局变量)
// ==============================================================================
var (
	// --- 基础资源指标 ---
	processCpuDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "cpu_seconds_total"),
		"Total user and system CPU time spent in seconds.",
		nil, nil,
	)
	processMemRssDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "resident_memory_bytes"),
		"Resident memory size in bytes.",
		nil, nil,
	)
	processThreadsDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "threads_count"),
		"Number of OS threads in the process.",
		nil, nil,
	)
	processStateDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "state_info"),
		"Current status of the process (exposed as a label).",
		[]string{"state"}, nil,
	)
	processMinFltDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "page_faults_minor_total"),
		"Total number of minor page faults (no disk I/O).",
		nil, nil,
	)
	processMajFltDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "page_faults_major_total"),
		"Total number of major page faults (requiring disk I/O).",
		nil, nil,
	)
	processVsizeDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "virtual_memory_bytes"),
		"Virtual memory size in bytes.",
		nil, nil,
	)
	processBlkioDelayDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "blkio_delay_seconds_total"),
		"Total time process waited for block I/O in seconds.",
		nil, nil,
	)

	// --- 上下文切换指标 ---
	processVolCtxDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "context_switches_voluntary_total"),
		"Total voluntary context switches.",
		nil, nil,
	)
	processNonVolCtxDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "context_switches_nonvoluntary_total"),
		"Total non-voluntary context switches (forced by kernel).",
		nil, nil,
	)

	// --- 进程级 IO 统计 ---
	processIoReadBytesDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "io_read_bytes_total"),
		"Total bytes actually read from the storage layer (physical reads).",
		nil, nil,
	)
	processIoWriteBytesDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "io_write_bytes_total"),
		"Total bytes actually written to the storage layer (physical writes).",
		nil, nil,
	)
	processIoRcharDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "io_rchar_bytes_total"),
		"Total bytes passed to read() syscalls (logical reads).",
		nil, nil,
	)
	processIoWcharDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "io_wchar_bytes_total"),
		"Total bytes passed to write() syscalls (logical writes).",
		nil, nil,
	)
	processIoSyscrDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "io_syscr_total"),
		"Total number of read I/O operations (syscalls).",
		nil, nil,
	)
	processIoSyscwDesc = prometheus.NewDesc(
		prometheus.BuildFQName(namespace, tendisProcess, "io_syscw_total"),
		"Total number of write I/O operations (syscalls).",
		nil, nil,
	)
)

// ==============================================================================
// 3. 智能缓存
// ==============================================================================
var instancePIDCache sync.Map

// ==============================================================================
// 4. 结构体定义 (已重命名)
// ==============================================================================
type ScrapeTendisProcessStat struct{}

// Name returns the name of the scraper.
func (ScrapeTendisProcessStat) Name() string {
	return tendisProcess
}

// Help returns the help string.
func (ScrapeTendisProcessStat) Help() string {
	return "Collects in-depth tendis process metrics via /proc/[pid]/{stat,status,io}"
}

// Version returns the tendis version.
func (ScrapeTendisProcessStat) Version() float64 {
	return 0
}

// ==============================================================================
// 5. 主控逻辑
// ==============================================================================
func (s ScrapeTendisProcessStat) Scrape(ctx context.Context, instance *TendisInstance, ch chan<- prometheus.Metric, logger *slog.Logger) error {
	// 阶段 1: 获取 PID
	pidStr, err := s.resolvePID(ctx, instance, logger)
	if err != nil {
		return err
	}

	// 阶段 2: 采集 /proc/[pid]/stat
	if err := s.collectProcStat(pidStr, ch, logger); err != nil {
		logger.Error("Failed to collect stat", "err", err)
	}

	// 阶段 3: 采集 /proc/[pid]/status
	if err := s.collectProcStatus(pidStr, ch, logger); err != nil {
		logger.Warn("Failed to collect status", "err", err)
	}

	// 阶段 4: 采集 /proc/[pid]/io
	if err := s.collectProcIO(pidStr, ch, logger); err != nil {
		logger.Warn("Failed to collect io", "err", err)
	}

	return nil
}

// ==============================================================================
// 子任务 1: 解析 PID
// ==============================================================================
func (s ScrapeTendisProcessStat) resolvePID(ctx context.Context, instance *TendisInstance, logger *slog.Logger) (string, error) {
	// ========================================================================
	// 1. 缓存检查 (逻辑保持不变)
	// ========================================================================
	if cachedPID, ok := instancePIDCache.Load(instance); ok {
		pidStr := cachedPID.(string)
		// 检查 /proc/<pid> 是否还存在，确保进程没重启
		if _, err := os.Stat(fmt.Sprintf("/proc/%s", pidStr)); err == nil {
			return pidStr, nil
		}
		// 如果不存在了，说明缓存失效，清理掉
		instancePIDCache.Delete(instance)
	}

	// ========================================================================
	// 2. 从 Tendis 获取 PID (这是核心变化)
	// MySQL 需要查文件路径再读文件，Tendis 直接问 INFO server 即可
	// ========================================================================

	// 执行 INFO server 命令
	infoStr, err := instance.Client.Info(ctx, "server").Result()
	if err != nil {
		logger.Error("Failed to execute INFO server", "err", err)
		return "", err
	}

	// ========================================================================
	// 3. 解析 process_id
	// 返回格式片段:
	// # Server
	// redis_version:6.2.6
	// ...
	// process_id:12345
	// ...
	// ========================================================================
	var pidStr string
	lines := strings.Split(infoStr, "\r\n")

	for _, line := range lines {
		if strings.HasPrefix(line, "process_id:") {
			parts := strings.Split(line, ":")
			if len(parts) >= 2 {
				pidStr = strings.TrimSpace(parts[1])
				break
			}
		}
	}

	if pidStr == "" {
		err := fmt.Errorf("process_id not found in INFO output")
		logger.Error("Failed to parse PID", "err", err)
		return "", err
	}

	// ========================================================================
	// 4. 更新缓存并返回
	// ========================================================================
	instancePIDCache.Store(instance, pidStr)
	logger.Debug("Successfully fetched and cached Tendis PID", "pid", pidStr)

	return pidStr, nil
}

// ==============================================================================
// 子任务 2: 解析 Stat
// ==============================================================================
func (s ScrapeTendisProcessStat) collectProcStat(pidStr string, ch chan<- prometheus.Metric, logger *slog.Logger) error {
	filePath := fmt.Sprintf("/proc/%s/stat", pidStr)
	data, err := os.ReadFile(filePath)
	if err != nil {
		return err
	}
	statStr := string(data)

	endOfComm := strings.LastIndex(statStr, ")")
	if endOfComm == -1 || len(statStr) <= endOfComm+2 {
		return fmt.Errorf("invalid stat file format")
	}
	fields := strings.Fields(statStr[endOfComm+2:])
	if len(fields) < 40 {
		return fmt.Errorf("stat fields too short")
	}
	logger.Debug("Successfully parsed stat file", "stat", filePath)

	stateStr := fields[0]
	minFlt, _ := strconv.ParseFloat(fields[7], 64)
	majFlt, _ := strconv.ParseFloat(fields[9], 64)
	utime, _ := strconv.ParseFloat(fields[11], 64)
	stime, _ := strconv.ParseFloat(fields[12], 64)
	threads, _ := strconv.ParseFloat(fields[17], 64)
	vsizeBytes, _ := strconv.ParseFloat(fields[20], 64)
	rssPages, _ := strconv.ParseFloat(fields[21], 64)
	blkioTicks, _ := strconv.ParseFloat(fields[39], 64)

	cpuSecondsTotal := (utime + stime) / linuxUserHz
	rssBytes := rssPages * float64(os.Getpagesize())

	ch <- prometheus.MustNewConstMetric(processStateDesc, prometheus.GaugeValue, 1.0, stateStr)
	ch <- prometheus.MustNewConstMetric(processThreadsDesc, prometheus.GaugeValue, threads)
	ch <- prometheus.MustNewConstMetric(processVsizeDesc, prometheus.GaugeValue, vsizeBytes)
	ch <- prometheus.MustNewConstMetric(processMemRssDesc, prometheus.GaugeValue, rssBytes)
	ch <- prometheus.MustNewConstMetric(processCpuDesc, prometheus.CounterValue, cpuSecondsTotal)
	ch <- prometheus.MustNewConstMetric(processMinFltDesc, prometheus.CounterValue, minFlt)
	ch <- prometheus.MustNewConstMetric(processMajFltDesc, prometheus.CounterValue, majFlt)
	ch <- prometheus.MustNewConstMetric(processBlkioDelayDesc, prometheus.CounterValue, blkioTicks/linuxUserHz)

	return nil
}

// ==============================================================================
// 子任务 3: 解析 Status
// ==============================================================================
func (s ScrapeTendisProcessStat) collectProcStatus(pidStr string, ch chan<- prometheus.Metric, logger *slog.Logger) error {
	filePath := fmt.Sprintf("/proc/%s/status", pidStr)
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()
	logger.Debug("Successfully parsed status file", "status", filePath)

	var volCtx, nonVolCtx float64
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "voluntary_ctxt_switches:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				volCtx, _ = strconv.ParseFloat(parts[1], 64)
			}
		}
		if strings.HasPrefix(line, "nonvoluntary_ctxt_switches:") {
			parts := strings.Fields(line)
			if len(parts) >= 2 {
				nonVolCtx, _ = strconv.ParseFloat(parts[1], 64)
			}
		}
	}

	ch <- prometheus.MustNewConstMetric(processVolCtxDesc, prometheus.CounterValue, volCtx)
	ch <- prometheus.MustNewConstMetric(processNonVolCtxDesc, prometheus.CounterValue, nonVolCtx)
	return nil
}

// ==============================================================================
// 子任务 4: 解析 IO
// ==============================================================================
func (s ScrapeTendisProcessStat) collectProcIO(pidStr string, ch chan<- prometheus.Metric, logger *slog.Logger) error {
	filePath := fmt.Sprintf("/proc/%s/io", pidStr)
	file, err := os.Open(filePath)
	if err != nil {
		return err
	}
	defer file.Close()
	logger.Debug("Successfully parsed io file", "io", filePath)

	var rchar, wchar, syscr, syscw, readBytes, writeBytes float64
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		val, _ := strconv.ParseFloat(parts[1], 64)

		switch parts[0] {
		case "rchar:":
			rchar = val
		case "wchar:":
			wchar = val
		case "syscr:":
			syscr = val
		case "syscw:":
			syscw = val
		case "read_bytes:":
			readBytes = val
		case "write_bytes:":
			writeBytes = val
		}
	}

	ch <- prometheus.MustNewConstMetric(processIoReadBytesDesc, prometheus.CounterValue, readBytes)
	ch <- prometheus.MustNewConstMetric(processIoWriteBytesDesc, prometheus.CounterValue, writeBytes)
	ch <- prometheus.MustNewConstMetric(processIoRcharDesc, prometheus.CounterValue, rchar)
	ch <- prometheus.MustNewConstMetric(processIoWcharDesc, prometheus.CounterValue, wchar)
	ch <- prometheus.MustNewConstMetric(processIoSyscrDesc, prometheus.CounterValue, syscr)
	ch <- prometheus.MustNewConstMetric(processIoSyscwDesc, prometheus.CounterValue, syscw)

	return nil
}
