package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	// 确保 go.mod module 名是 tendis_exporter，否则需修改此处路径
	"tendis_exporter/collector"

	"github.com/alecthomas/kingpin/v2"
	"github.com/prometheus/client_golang/prometheus"
	versioncollector "github.com/prometheus/client_golang/prometheus/collectors/version"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/prometheus/common/promslog"
	"github.com/prometheus/common/promslog/flag"
	"github.com/prometheus/common/version"
	"github.com/prometheus/exporter-toolkit/web"
	webflag "github.com/prometheus/exporter-toolkit/web/kingpinflag"
)

// ==============================================================================
// 1. 全局配置 Flags
// ==============================================================================
var (
	metricsPath = kingpin.Flag(
		"web.telemetry-path",
		"Path under which to expose metrics.",
	).Default("/metrics").String()

	// toolkitFlags 会自动注册 --web.listen-address，默认端口 :9121

	probePath = kingpin.Flag(
		"web.probe-path",
		"Path under which to expose metrics. target, data_dir, service_name, password, password_file. like /probe?target=192.168.0.1:6379&data_dir=/data&service_name=tendis1",
	).Default("/probe").String()

	timeoutOffset = kingpin.Flag(
		"timeout-offset",
		"Offset to subtract from timeout in seconds.",
	).Default("0.25").Float64()

	// --- Tendis 连接配置 ---
	tendisAddress = kingpin.Flag(
		"tendis.addr",
		"Address of the Tendis instance to scrape: host:port (default target).",
	).Default("").String()

	tendisPassword = kingpin.Flag(
		"tendis.password",
		"Password of the Tendis instance.",
	).Default("").String()

	// Toolkit flags (用于 TLS/Auth 等高级 Web 配置，并管理监听地址)
	toolkitFlags = webflag.AddFlags(kingpin.CommandLine, ":9121")
)

// ==============================================================================
// 2. 注册采集器 (Scrapers)
// ==============================================================================
// 在这里列出所有可用的 Scraper，value 代表是否默认开启
var scrapers = map[collector.Scraper]bool{
	collector.ScrapeTendisInfo{}:        true,  // 对应 collector/tendis_info.go
	collector.ScrapeTendisProcessStat{}: false, // 对应 collector/tendis_process_stat.go
}

func init() {
	prometheus.MustRegister(versioncollector.NewCollector("tendis_exporter"))
}

// ==============================================================================
// 3. Exporter 结构体 (胶水层)
// ==============================================================================
type TendisExporter struct {
	ctx      context.Context
	target   string
	scrapers []collector.Scraper
	logger   *slog.Logger
	instance *collector.TendisInstance
}

// getPasswordFromConf 统一处理从配置文件中提取 requirepass 密码的逻辑
func getPasswordFromConf(filePath string) (string, error) {
	fileBytes, err := os.ReadFile(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to read config file %s: %w", filePath, err)
	}

	lines := strings.Split(string(fileBytes), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "requirepass ") || strings.HasPrefix(line, "requirepass\t") {
			rawPass := strings.TrimSpace(line[11:])
			return strings.Trim(rawPass, `"'`), nil
		}
	}

	return "", fmt.Errorf("requirepass directive not found in %s", filePath)
}

// 修改方法签名，增加 reqPassword, data_dir, serviceName
// 修改方法签名，增加 passwordFile
func NewTendisExporter(ctx context.Context, target string, reqPassword string, passwordFile string, data_dir string, serviceName string, scrapers []collector.Scraper, logger *slog.Logger) (*TendisExporter, error) {
	// 1. 默认使用启动时的全局 Flag 配置
	addr := *tendisAddress
	password := *tendisPassword

	// 2. 覆盖地址
	if target != "" {
		addr = target
	}

	// 3. 核心业务逻辑：按照优先级决定密码获取方式
	if reqPassword != "" {
		// 优先级 1: URL 中直接传了明文密码
		password = reqPassword
	} else if passwordFile != "" {
		// 优先级 2: URL 传了具体的配置文件路径，直接读取
		pwd, err := getPasswordFromConf(passwordFile)
		if err != nil {
			return nil, err // 读取失败直接抛错，方便 Prometheus 记录抓取失败
		}
		password = pwd
	} else if data_dir != "" && serviceName != "" {
		// 优先级 3: URL 传了目录和实例名，拼接后读取
		filePath := fmt.Sprintf("/%s/tendis/conf/tendis.conf.%s", data_dir, serviceName)
		pwd, err := getPasswordFromConf(filePath)
		if err != nil {
			return nil, err
		}
		password = pwd
	}
	// 如果都没命中，就自动降级使用全局默认的 *tendisPassword

	// 4. 调用 collector 包中的连接工厂
	instance, err := collector.NewTendisInstance(ctx, addr, password)
	if err != nil {
		return nil, err
	}

	return &TendisExporter{
		ctx:      ctx,
		target:   addr,
		scrapers: scrapers,
		logger:   logger,
		instance: instance,
	}, nil
}

// Describe 实现 Prometheus Collector 接口
func (e *TendisExporter) Describe(ch chan<- *prometheus.Desc) {
	// 动态指标不需要在这里描述，Prometheus 允许 Describe 为空
	ch <- prometheus.NewDesc("tendis_exporter_up", "Was the last scrape of Tendis successful.", nil, nil)
}

// Collect 实现 Prometheus Collector 接口 (核心采集循环)
func (e *TendisExporter) Collect(ch chan<- prometheus.Metric) {
	// 确保采集结束后关闭 Tendis 连接
	defer e.instance.Close()

	up := 1.0
	start := time.Now()

	// 遍历执行所有启用的 Scraper
	for _, scraper := range e.scrapers {
		if err := scraper.Scrape(e.ctx, e.instance, ch, e.logger); err != nil {
			e.logger.Error("Error scraping for scraper", "scraper", scraper.Name(), "err", err)
			// 只有当 INFO 采集失败时，才认为服务 DOWN 了
			if scraper.Name() == "tendis_info" {
				up = 0
			}
		}
	}

	// 记录自身监控指标
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc("tendis_exporter_scrape_duration_seconds", "Duration of the scrape.", nil, nil),
		prometheus.GaugeValue,
		time.Since(start).Seconds(),
	)
	ch <- prometheus.MustNewConstMetric(
		prometheus.NewDesc("tendis_exporter_up", "Was the last scrape of Tendis successful.", nil, nil),
		prometheus.GaugeValue,
		up,
	)
}

// ==============================================================================
// 4. HTTP Handler (处理每次请求)
// ==============================================================================
func newHandler(enabledScrapers []collector.Scraper, logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// A. 解析参数 (新增解析 data_dir 和 service_name)
		target := r.URL.Query().Get("target")
		data_dir := r.URL.Query().Get("data_dir")          // 新增
		serviceName := r.URL.Query().Get("service_name")   // 新增
		reqPassword := r.URL.Query().Get("password")       // 可选：直接通过 URL 传密码兜底
		passwordFile := r.URL.Query().Get("password_file") // 新增：直接传入配置文件路径

		collects := r.URL.Query()["collect[]"]

		// B. 过滤 Scraper
		var finalScrapers []collector.Scraper
		// ... 保持原有过滤逻辑不变 ...
		if len(collects) > 0 {
			filter := make(map[string]bool)
			for _, c := range collects {
				filter[c] = true
			}
			for _, s := range enabledScrapers {
				if filter[s.Name()] {
					finalScrapers = append(finalScrapers, s)
				}
			}
		} else {
			finalScrapers = enabledScrapers
		}

		// C. 处理超时 Context
		ctx := r.Context()
		timeoutSeconds, err := getScrapeTimeoutSeconds(r, *timeoutOffset)
		// ... 保持原有超时逻辑不变 ...
		if err != nil {
			logger.Error("Error getting timeout", "err", err)
		}
		if timeoutSeconds > 0 {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(ctx, time.Duration(timeoutSeconds*float64(time.Second)))
			defer cancel()
		}

		// D. 创建独立的 Registry
		registry := prometheus.NewRegistry()

		// E. 实例化 Exporter 并注册 (增加 passwordFile 传参)
		exporter, err := NewTendisExporter(ctx, target, reqPassword, passwordFile, data_dir, serviceName, finalScrapers, logger)
		if err != nil {
			logger.Error("Failed to create exporter", "err", err)
			http.Error(w, fmt.Sprintf("Failed to connect to Tendis: %s", err), http.StatusInternalServerError)
			return
		}
		registry.MustRegister(exporter)

		// F. 代理给 Promhttp 处理
		h := promhttp.HandlerFor(registry, promhttp.HandlerOpts{})
		h.ServeHTTP(w, r)
	}
}

// getScrapeTimeoutSeconds 解析 Prometheus 传递的超时头
func getScrapeTimeoutSeconds(r *http.Request, offset float64) (float64, error) {
	var timeoutSeconds float64
	if v := r.Header.Get("X-Prometheus-Scrape-Timeout-Seconds"); v != "" {
		var err error
		timeoutSeconds, err = strconv.ParseFloat(v, 64)
		if err != nil {
			return 0, fmt.Errorf("failed to parse timeout header: %v", err)
		}
	}
	if timeoutSeconds == 0 {
		return 0, nil
	}
	if offset >= timeoutSeconds {
		return 0, fmt.Errorf("timeout offset (%f) should be lower than scrape timeout (%f)", offset, timeoutSeconds)
	}
	return timeoutSeconds - offset, nil
}

// ==============================================================================
// 5. Main 入口
// ==============================================================================
func main() {
	// 1. 自动生成 Scraper Flags (--collect.tendis_info 等)
	scraperFlags := map[collector.Scraper]*bool{}
	for scraper, enabledByDefault := range scrapers {
		defaultOn := "false"
		if enabledByDefault {
			defaultOn = "true"
		}
		f := kingpin.Flag("collect."+scraper.Name(), scraper.Help()).Default(defaultOn).Bool()
		scraperFlags[scraper] = f
	}

	// 2. 解析命令行参数
	promslogConfig := &promslog.Config{}
	flag.AddFlags(kingpin.CommandLine, promslogConfig)
	kingpin.Version(version.Print("tendis_exporter"))
	kingpin.HelpFlag.Short('h')
	kingpin.Parse()
	logger := promslog.New(promslogConfig)

	logger.Info("Starting tendis_exporter", "version", version.Info())

	// 3. 确定启用的 Scrapers
	enabledScrapers := []collector.Scraper{}
	for scraper, enabled := range scraperFlags {
		if *enabled {
			logger.Info("Scraper enabled", "scraper", scraper.Name())
			enabledScrapers = append(enabledScrapers, scraper)
		}
	}

	// 4. 设置 HTTP 路由
	handlerFunc := newHandler(enabledScrapers, logger)

	// A. 将 handler 包装一层自带的监控 (记录自身 HTTP 请求状态、耗时等)
	instrumentedHandler := promhttp.InstrumentMetricHandler(prometheus.DefaultRegisterer, handlerFunc)

	// B. 注册标准 Metrics 路径
	http.Handle(*metricsPath, instrumentedHandler)

	// C. 注册 Probe 路径 (兼容 Blackbox 风格)，同时防御性判断以避免路由冲突导致 panic
	if *metricsPath != "/probe" {
		http.Handle("/probe", instrumentedHandler)
	}

	// 首页 (Landing Page)
	if *metricsPath != "/" && *metricsPath != "" {
		landingConfig := web.LandingConfig{
			Name:        "Tendis Exporter",
			Description: "High-performance Prometheus Exporter for Tendis",
			Version:     version.Info(),
			Links: []web.LandingLinks{
				{Address: *metricsPath, Text: "Metrics"},
				{Address: "/probe", Text: "Probe"},
			},
		}
		landingPage, err := web.NewLandingPage(landingConfig)
		if err != nil {
			logger.Error("Error creating landing page", "err", err)
			os.Exit(1)
		}
		http.Handle("/", landingPage)
	}

	// 5. 启动服务
	srv := &http.Server{}
	logger.Info("Starting server", "listen_address", ":9121")
	if err := web.ListenAndServe(srv, toolkitFlags, logger); err != nil {
		logger.Error("Error starting HTTP server", "err", err)
		os.Exit(1)
	}
}
