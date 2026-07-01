# sysinfo-cli — 开发 / 测试 / 部署 / 推送
#
# 常用:
#   make              显示帮助
#   make test         本地测试
#   make install      安装到系统
#   make deploy       测试通过后安装
#   make push         推送到 GitHub

SHELL       := /bin/bash
ROOT        := $(CURDIR)
SYSINFO     := $(ROOT)/src/sysinfo.sh
SUDO        := sudo
INSTALL     := $(ROOT)/install.sh
BRANCH      := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)
DOCS_PORT   ?= 8099
RUN_TIMEOUT ?= 5
DOCKER      := $(ROOT)/scripts/docker-cmd.sh
DOCKER_SMOKE_DISTROS ?= debian alpine openwrt

SRC_SCRIPTS := $(wildcard $(ROOT)/src/*.sh) \
               $(ROOT)/install.sh $(ROOT)/uninstall.sh \
               $(wildcard $(ROOT)/scripts/*.sh) \
               $(wildcard $(ROOT)/tests/*.sh)

.PHONY: help all dev run run-live help-cli syntax lint test validate test-throttle \
        test-notify test-all install install-zh install-en install-reset uninstall \
        reinstall reload-config deploy push ship docs docs-serve docs-stop docker-build docker-build-distros docker-test \
        docker-smoke docker-smoke-distros docker-test-distros docker-test-distros-regression docker-shell clean chmod

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

help: ## 显示此帮助
	@printf '\n  sysinfo-cli Makefile\n\n'
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@printf '\n  变量: DOCS_PORT=%s  RUN_TIMEOUT=%s  BRANCH=%s\n\n' \
		'$(DOCS_PORT)' '$(RUN_TIMEOUT)' '$(BRANCH)'

all: test validate ## 运行全部测试（不含 Docker）

# ---------------------------------------------------------------------------
# 开发
# ---------------------------------------------------------------------------

dev: run ## 别名: 本地运行一次面板

run: ## 本地运行面板（非交互，$(RUN_TIMEOUT)s 超时）
	@timeout $(RUN_TIMEOUT) $(SYSINFO) 2>&1 || true

run-live: ## 本地实时面板（交互，Ctrl+C 退出）
	@$(SYSINFO)

help-cli: ## 显示 sysinfo CLI 帮助
	@$(SYSINFO) -h

syntax lint: chmod ## bash -n 语法检查全部脚本
	@fail=0; \
	for f in $(SRC_SCRIPTS); do \
		if bash -n "$$f" 2>/dev/null; then \
			printf '  ✓ %s\n' "$${f#$(ROOT)/}"; \
		else \
			printf '  ✗ %s\n' "$${f#$(ROOT)/}"; \
			fail=1; \
		fi; \
	done; \
	exit $$fail

chmod: ## 确保脚本可执行
	@chmod +x $(SRC_SCRIPTS) 2>/dev/null || true

# ---------------------------------------------------------------------------
# 测试
# ---------------------------------------------------------------------------

test: chmod ## 运行 tests/test_sysinfo.sh（生成 tests/test_report.md）
	@bash $(ROOT)/tests/test_sysinfo.sh
	@printf '\n  报告: tests/test_report.md\n'

validate: chmod ## 运行 tests/server_validate.sh（完整服务器验证）
	@bash $(ROOT)/tests/server_validate.sh

test-throttle: chmod ## 限速 / tc 诊断
	@bash $(ROOT)/scripts/test_throttle.sh

test-notify: ## 推送通道测试（需已配置 notify；优先用已安装 sysinfo）
	@cmd=$$(command -v sysinfo 2>/dev/null || echo "$(SYSINFO)"); \
	$$cmd --notify-test

test-notify-check: ## 评估推送规则（cron 同款；优先用已安装 sysinfo）
	@cmd=$$(command -v sysinfo 2>/dev/null || echo "$(SYSINFO)"); \
	$$cmd --notify-check

test-all: test validate test-throttle ## 本地 + 服务器验证 + 限速诊断

# ---------------------------------------------------------------------------
# 安装 / 部署
# ---------------------------------------------------------------------------

install: chmod ## sudo ./install.sh（保留已有 config.yaml）
	@$(SUDO) $(INSTALL)

install-zh: chmod ## 安装并设置中文
	@$(SUDO) $(INSTALL) --lang zh

install-en: chmod ## 安装并设置英文
	@$(SUDO) $(INSTALL) --lang en

install-reset: chmod ## 安装并重置 config.yaml（自动备份旧配置）
	@$(SUDO) $(INSTALL) --overwrite-config

uninstall: ## sudo ./uninstall.sh
	@$(SUDO) $(ROOT)/uninstall.sh

reinstall: uninstall install ## 卸载后重新安装

reload-config: ## 重新加载 /etc/sysinfo/config.yaml
	@$(SUDO) $$(command -v sysinfo 2>/dev/null || echo "$(SYSINFO)") -r

deploy: test validate install ## 测试通过后安装到本机

# ---------------------------------------------------------------------------
# Git 推送
# ---------------------------------------------------------------------------

push: ## git push origin $(BRANCH)
	@git push origin $(BRANCH)

ship: deploy push ## 测试 → 安装 → 推送（需已有 commit）

# ---------------------------------------------------------------------------
# 文档 / Docker
# ---------------------------------------------------------------------------

docs: docs-serve ## 别名: 启动文档静态服务

# Free DOCS_PORT: stop Docker containers publishing it, then kill listeners.
docs-stop: ## 释放 $(DOCS_PORT)（停止占用该端口的 Docker 容器与进程）
	@port='$(DOCS_PORT)'; \
	freed=0; \
	if command -v docker >/dev/null 2>&1; then \
		cids=$$($(DOCKER) ps -q --filter "publish=$$port" 2>/dev/null); \
		if [ -n "$$cids" ]; then \
			printf '  停止占用端口 %s 的 Docker 容器: %s\n' "$$port" "$$cids"; \
			$(DOCKER) stop $$cids >/dev/null 2>&1 || true; \
			freed=1; \
		fi; \
	fi; \
	if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$$port" 2>/dev/null | grep -q LISTEN; then \
		pids=$$(ss -ltnp "sport = :$$port" 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | sort -u); \
		if [ -n "$$pids" ]; then \
			printf '  结束占用端口 %s 的进程: %s\n' "$$port" "$$pids"; \
			kill $$pids 2>/dev/null || true; \
			sleep 0.2; \
			kill -9 $$pids 2>/dev/null || true; \
			freed=1; \
		fi; \
	fi; \
	if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$$port" 2>/dev/null | grep -q LISTEN; then \
		if command -v fuser >/dev/null 2>&1; then \
			printf '  释放端口 %s (fuser)...\n' "$$port"; \
			fuser -k "$$port/tcp" >/dev/null 2>&1 || true; \
			freed=1; \
		fi; \
	fi; \
	if [ "$$freed" = 0 ]; then \
		if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$$port" 2>/dev/null | grep -q LISTEN; then \
			printf '  警告: 端口 %s 仍被占用，请手动检查 (ss -ltnp sport = :%s)\n' "$$port" "$$port"; \
		else \
			printf '  端口 %s 未被占用\n' "$$port"; \
		fi; \
	fi; \
	sleep 0.2

docs-serve: docs-stop ## 启动 docs/ 静态服务 http://0.0.0.0:$(DOCS_PORT)（端口占用时自动释放）
	@port='$(DOCS_PORT)'; \
	printf '  主页: http://127.0.0.1:%s/\n' "$$port"; \
	printf '  文档: http://127.0.0.1:%s/wiki.html\n' "$$port"; \
	python3 -m http.server "$$port" --bind 0.0.0.0 --directory $(ROOT)/docs

docker-build: ## 构建测试镜像 sysinfo-cli:dev (Debian)
	$(DOCKER) build -t sysinfo-cli:dev $(ROOT)

docker-build-distros: chmod ## 构建 8 个发行版 install-test 镜像 (docker/Dockerfile.install-test)
	@bash $(ROOT)/docker/build-distros.sh

docker-test: docker-build ## 在容器内运行 test + validate
	$(DOCKER) run --rm sysinfo-cli:dev bash -lc '\
		apt-get update -qq && apt-get install -y -qq zsh >/dev/null 2>&1; \
		bash tests/test_sysinfo.sh && bash tests/server_validate.sh'

docker-smoke: chmod ## 快速 Docker 冒烟（Debian 单发行版）
	@RUN_TIMEOUT=180 bash $(ROOT)/tests/docker_distros.sh debian

docker-smoke-distros: chmod ## 代表性 Docker 冒烟（默认: $(DOCKER_SMOKE_DISTROS)）
	@RUN_TIMEOUT=240 bash $(ROOT)/tests/docker_distros.sh $(DOCKER_SMOKE_DISTROS)

docker-test-distros: chmod ## 全发行版 Docker 安装冒烟测试（不跑重回归）
	@bash $(ROOT)/tests/docker_distros.sh

docker-test-distros-regression: chmod ## 全发行版 Docker 回归测试（NAT/流量/限速/重置/banner）
	@REGRESSION=1 RUN_TIMEOUT=420 bash $(ROOT)/tests/docker_distros.sh

docker-shell: docker-build ## 进入容器交互 shell
	$(DOCKER) run --rm -it sysinfo-cli:dev

# ---------------------------------------------------------------------------
# 清理
# ---------------------------------------------------------------------------

clean: ## 删除测试生成的临时文件
	@rm -f $(ROOT)/tests/test_report.md \
	       $(ROOT)/tests/test_config.yaml \
	       $(ROOT)/tests/validate_config.yaml \
	       $(ROOT)/tests/docker_distros_report.md \
	       $(ROOT)/tests/*.log
	@printf '  已清理 tests/ 生成物\n'
