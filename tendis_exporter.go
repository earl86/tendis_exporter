package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strconv"
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

	timeoutOffset = kingpin.Flag(
		"timeout-offset",
		"Offset to subtract from timeout in seconds.",
	).Default("0.25").Float64()

	// --- Tendis 连接配置 ---
	tendisAddress = kingpin.Flag(
		"tendis.addr",
		"Address of the Tendis instance to scrape (default target).",
	).Default("localhost:6379").String()

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

// NewTendisExporter 创建一个新的 Exporter 实例，并在内部建立 Tendis 连接
func NewTendisExporter(ctx context.Context, target string, scrapers []collector.Scraper, logger *slog.Logger) (*TendisExporter, error) {
	// 如果 URL 参数没传 target，则使用启动参数里的默认地址
	addr := target
	if addr == "" {
		addr = *tendisAddress
	}

	// 调用 collector 包中的连接工厂
	instance, err := collector.NewTendisInstance(ctx, addr, *tendisPassword)
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
		// A. 解析参数
		target := r.URL.Query().Get("target")
		collects := r.URL.Query()["collect[]"]

		// B. 过滤 Scraper
		var finalScrapers []collector.Scraper
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
		if err != nil {
			logger.Error("Error getting timeout", "err", err)
		}
		if timeoutSeconds > 0 {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(ctx, time.Duration(timeoutSeconds*float64(time.Second)))
			defer cancel()
		}

		// D. 创建独立的 Registry (关键步骤)
		// 每次请求都使用新的 Registry，支持并发抓取不同 Target
		registry := prometheus.NewRegistry()

		// E. 实例化 Exporter 并注册
		exporter, err := NewTendisExporter(ctx, target, finalScrapers, logger)
		if err != nil {
			logger.Error("Failed to create exporter", "err", err)
			// 连接失败直接返回 500，Prometheus 会记录为 scrape_failed
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

	// 标准 Metrics 路径
	http.Handle(*metricsPath, promhttp.InstrumentMetricHandler(prometheus.DefaultRegisterer, handlerFunc))

	// Probe 路径 (兼容 Blackbox 风格)
	http.Handle("/probe", handlerFunc)

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
	// 修改日志信息，不再打印 listenAddress 变量
	logger.Info("Starting server", "listen_address", ":9121") // 默认端口，或者你可以只写 "Starting server"
	if err := web.ListenAndServe(srv, toolkitFlags, logger); err != nil {
		logger.Error("Error starting HTTP server", "err", err)
		os.Exit(1)
	}
}
