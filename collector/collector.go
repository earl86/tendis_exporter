package collector

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/prometheus/client_golang/prometheus"
)

// ==============================================================================
// 1. 全局常量
// ==============================================================================
const (
	// Namespace defines the common namespace for all tendis metrics.
	namespace = "tendis"
)

// ==============================================================================
// 2. 正则表达式
// ==============================================================================
var (
	// 用于清洗指标名，将非字母数字字符替换为下划线
	metricNameRE = regexp.MustCompile(`[^a-zA-Z0-9_]`)
)

// ==============================================================================
// 3. 公用辅助函数 (Utils)
// ==============================================================================

// NewDesc is a helper to create a new Prometheus description.
func NewDesc(subsystem, name, help string) *prometheus.Desc {
	return prometheus.NewDesc(
		prometheus.BuildFQName(namespace, subsystem, name),
		help, nil, nil,
	)
}

// SanitizeMetricName replaces non-alphanumeric characters with underscores.
// Example: "cmdstat_get" -> "cmdstat_get", "cluster-enabled" -> "cluster_enabled"
func SanitizeMetricName(name string) string {
	return metricNameRE.ReplaceAllString(name, "_")
}

// ParseSafeFloat converts a string to float64, returning 0.0 on error.
// Useful for "lazy" parsing where we don't want to halt execution on bad data.
func ParseSafeFloat(s string) float64 {
	val, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0.0
	}
	return val
}

// ParseTendisStatus converts Tendis status strings to float values.
// Tendis often returns "ok", "on", "online" for success/up states.
func ParseTendisStatus(s string) float64 {
	switch strings.ToLower(s) {
	case "ok", "up", "online", "yes", "true", "enabled", "on":
		return 1.0
	case "fail", "down", "offline", "no", "false", "disabled", "off":
		return 0.0
	}
	// If it's already a number, return it
	return ParseSafeFloat(s)
}
