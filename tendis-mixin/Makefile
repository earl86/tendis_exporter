JSONNET_FMT_OPTS := -n 2 --max-blank-lines 2 --string-style s --comment-style s

# 本地沙盒目录
LOCAL_BIN := $(shell pwd)/.bin

# ==========================================
# 1. 动态探测机制 (核心魔法)
# ==========================================
# 尝试在系统的 PATH 中查找工具是否存在
JB_BIN := $(shell command -v jb 2> /dev/null)
MIXTOOL_BIN := $(shell command -v mixtool 2> /dev/null)
JSONNETFMT_BIN := $(shell command -v jsonnetfmt 2> /dev/null)
JSONNET_BIN := $(shell command -v jsonnet 2> /dev/null)

# 如果系统找到了，就用系统的绝对路径；如果没找到，就把目标设定为本地的 .bin/xxx
JB := $(if $(JB_BIN),$(JB_BIN),$(LOCAL_BIN)/jb)
MIXTOOL := $(if $(MIXTOOL_BIN),$(MIXTOOL_BIN),$(LOCAL_BIN)/mixtool)
JSONNETFMT := $(if $(JSONNETFMT_BIN),$(JSONNETFMT_BIN),$(LOCAL_BIN)/jsonnetfmt)
JSONNET := $(if $(JSONNET_BIN),$(JSONNET_BIN),$(LOCAL_BIN)/jsonnet)

JSONNET_FMT_CMD := $(JSONNETFMT) $(JSONNET_FMT_OPTS)

.PHONY: all fmt lint build clean

default: build
all: fmt lint build

# ==========================================
# 2. 自动下载规则 (仅在系统无该工具时触发)
# ==========================================
# Make 的特性：如果上面的变量解析为系统路径(如 /usr/bin/jb)，由于文件已存在，这里的规则将直接被跳过！
$(LOCAL_BIN)/jb:
	@echo ">> System 'jb' not found. Installing to $(LOCAL_BIN)..."
	@mkdir -p $(LOCAL_BIN)
	GOBIN=$(LOCAL_BIN) go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest

$(LOCAL_BIN)/mixtool:
	@echo ">> System 'mixtool' not found. Installing to $(LOCAL_BIN)..."
	@mkdir -p $(LOCAL_BIN)
	GOBIN=$(LOCAL_BIN) go install github.com/monitoring-mixins/mixtool/cmd/mixtool@latest

$(LOCAL_BIN)/jsonnetfmt:
	@echo ">> System 'jsonnetfmt' not found. Installing to $(LOCAL_BIN)..."
	@mkdir -p $(LOCAL_BIN)
	GOBIN=$(LOCAL_BIN) go install github.com/google/go-jsonnet/cmd/jsonnetfmt@latest

# 新增的 jsonnet 自动安装规则
$(LOCAL_BIN)/jsonnet:
	@echo ">> System 'jsonnet' not found. Installing to $(LOCAL_BIN)..."
	@mkdir -p $(LOCAL_BIN)
	GOBIN=$(LOCAL_BIN) go install github.com/google/go-jsonnet/cmd/jsonnet@latest

# ==========================================
# 3. 核心构建逻辑
# ==========================================
# 自动初始化和拉取 grafonnet 依赖
jsonnetfile.json jsonnetfile.lock.json: $(JB)
	@echo ">> Initializing jsonnetfile and installing grafonnet..."
	$(JB) init
	$(JB) install github.com/grafana/grafonnet/gen/grafonnet-latest@main

vendor: $(JB) jsonnetfile.json jsonnetfile.lock.json
	$(JB) install

fmt: vendor $(JSONNETFMT)
	find . -name 'vendor' -prune -o -name '*.libsonnet' -print -o -name '*.jsonnet' -print | \
		xargs -n 1 -- $(JSONNET_FMT_CMD) -i

lint: vendor $(JSONNETFMT) $(MIXTOOL)
	find . -name 'vendor' -prune -o -name '*.libsonnet' -print -o -name '*.jsonnet' -print | \
		while read f; do \
			$(JSONNET_FMT_CMD) "$$f" | diff -u "$$f" -; \
		done
	$(MIXTOOL) lint -J vendor mixin.libsonnet

# 将 $(JSONNET) 添加为 build 的前置依赖
build: clean vendor $(JSONNET) $(MIXTOOL)
	@echo ">> Generating Prometheus rules and Grafana dashboards..."
	$(MIXTOOL) generate all -J vendor mixin.libsonnet
	@echo ">> Build successful!"
	@echo ">> Check alerts.yaml, rules.yaml and dashboards_out/tendis-overview.json"

clean:
	rm -rf dashboards_out alerts.yaml rules.yaml
