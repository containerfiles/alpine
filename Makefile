IMAGE_NAME := $(notdir $(CURDIR))
HOST_DIR := /tmp/container/$(IMAGE_NAME)
TTY_FLAG := --tty
VOLUMES := --volume "$(HOST_DIR):/mnt/shared"
HEALTH_TIMEOUT := 10
BUILD_TIMEOUT := 120

-include container.conf

.DEFAULT_GOAL := help
.PHONY: status build run mcp stop clean dns nuke help pulse _pulse _dns_check _build_check

# ============================================================
# Status
# ============================================================
status:
	@echo ""
	@echo "\033[33mVersion:\033[0m"
	@container --version
	@echo ""
	@echo "\033[33mBuilder:\033[0m"
	@container builder status
	@echo ""
	@echo "\033[33mDNS Domain:\033[0m"
	@container system property get dns.domain
	@echo ""
	@echo "\033[33mHost DNS (.lab):\033[0m"
	@if container system dns list 2>/dev/null | grep -q '^lab$$'; then \
		echo "  Container DNS: \033[32mactive\033[0m"; \
	else \
		echo "  Container DNS: \033[31mnot configured\033[0m"; \
	fi
	@if [ -f /etc/resolver/lab ]; then \
		echo "  Host resolver: \033[32m/etc/resolver/lab exists\033[0m"; \
	else \
		echo "  Host resolver: \033[31mmissing\033[0m (run 'make dns')"; \
	fi
	@echo ""
	@echo "\033[33mImages:\033[0m"
	@container image list --verbose
	@echo ""
	@echo "\033[33mContainers:\033[0m"
	@container list --all

# ============================================================
# Health check
# ============================================================
pulse:
	@container system start >/dev/null 2>&1 || true
	@if perl -e 'alarm shift; exec @ARGV' $(HEALTH_TIMEOUT) container builder status >/dev/null 2>&1; then \
		echo "\033[32mResponsive\033[0m"; \
	else \
		echo "\033[31mUnresponsive\033[0m"; \
	fi

_pulse:
	@container system start >/dev/null 2>&1 || true
	@echo "Checking builder health..."
	@if perl -e 'alarm shift; exec @ARGV' $(HEALTH_TIMEOUT) container builder status >/dev/null 2>&1; then \
		echo "\033[32mBuilder OK\033[0m"; \
	else \
		echo "\033[31mBuilder not responding. Running nuke and clean...\033[0m"; \
		$(MAKE) nuke; \
		$(MAKE) clean; \
		echo ""; \
	fi

_dns_check:
	@if ! container system dns list 2>/dev/null | grep -q '^lab$$'; then \
		echo "\033[33mSetting up .lab DNS domain (first-time setup)...\033[0m"; \
		sudo container system dns create lab; \
	fi
	@if [ "$$(container system property get dns.domain 2>/dev/null)" != "lab" ]; then \
		container system property set dns.domain lab >/dev/null 2>&1; \
	fi
	@if [ ! -f /etc/resolver/lab ]; then \
		echo "\033[33mCreating /etc/resolver/lab...\033[0m"; \
		echo "domain lab\nsearch lab\nnameserver 127.0.0.1\nport 2053" | sudo tee /etc/resolver/lab >/dev/null; \
	fi

_build_check:
	@if ! container image list 2>/dev/null | grep -qw '$(IMAGE_NAME)'; then \
		echo "\033[33mImage '$(IMAGE_NAME)' not found. Building...\033[0m"; \
		perl -e 'alarm shift; exec @ARGV' $(BUILD_TIMEOUT) container build --no-cache --tag "$(IMAGE_NAME)" .; \
	fi

# ============================================================
# Build
# ============================================================
build: _pulse
	@perl -e 'alarm shift; exec @ARGV' $(BUILD_TIMEOUT) container build --no-cache --tag "$(IMAGE_NAME)" .

# ============================================================
# Run
# ============================================================
run: _pulse _dns_check _build_check
	@mkdir -p "$(HOST_DIR)"
	@echo "Spawning ephemeral shell at \033[36m$(IMAGE_NAME).lab\033[0m"
	container run $(strip --remove --name $(IMAGE_NAME) --interactive $(TTY_FLAG) $(VOLUMES) $(PORTS) $(ENV_VARS) $(EXTRA_FLAGS)) "$(IMAGE_NAME)"

# ============================================================
# MCP (stdio mode for MCP servers)
# ============================================================
mcp: _pulse _build_check
	@container run $(strip --remove --name $(IMAGE_NAME) $(ENV_VARS) $(EXTRA_FLAGS)) "$(IMAGE_NAME)"

# ============================================================
# Stop
# ============================================================
stop:
	@echo "Single containers exit with Ctrl+C"
	@echo "To force stop: container stop $(IMAGE_NAME)"

# ============================================================
# Clean
# ============================================================
clean:
	@container system start >/dev/null 2>&1 || true
	@echo "Removing $(IMAGE_NAME) image..."
	@container image rm "$(IMAGE_NAME)" || true
	@echo ""
	@echo "Pruning unused images..."
	@container image prune --all || true
	@echo ""
	@echo "Pruning unused volumes..."
	@container volume prune || true
	@echo ""
	@echo "\033[32mDone!\033[0m"

# ============================================================
# DNS setup
# ============================================================
dns: _dns_check
	@echo ""
	@echo "\033[32mDone!\033[0m Containers will be accessible at \033[36m<container-name>.lab\033[0m"
	@echo ""
	@echo "DNS domains:"
	@container system dns list
	@echo ""
	@echo "Resolver file:"
	@cat /etc/resolver/lab 2>/dev/null || echo "(not found)"

# ============================================================
# Nuke (reset builder)
# ============================================================
nuke:
	@echo "Force killing builder processes by PID..."
	@ps aux | grep -E 'container (build|builder|system)|buildkit|container-runtime-linux' | grep -v grep | awk '{print $$2}' | xargs kill -9 2>/dev/null || true
	@sleep 2
	@echo "Restarting builder..."
	@container builder start --memory 4G >/dev/null 2>&1 &
	@sleep 5
	@if perl -e 'alarm shift; exec @ARGV' 10 container builder status >/dev/null 2>&1; then \
		echo "\033[32mBuilder recovered\033[0m"; \
	else \
		echo "\033[31mBuilder still unresponsive\033[0m"; \
	fi

# ============================================================
# Help
# ============================================================
help:
	@echo ""
	@echo "\033[1mUsage:\033[0m make \033[36m[target]\033[0m"
	@echo ""
	@echo "\033[33mTargets:\033[0m"
	@echo "  \033[36mstatus\033[0m  \033[90m-\033[0m \033[32mShow builder, DNS, images, and containers\033[0m"
	@echo "  \033[36mbuild\033[0m   \033[90m-\033[0m \033[32mBuild the container image\033[0m"
	@echo "  \033[36mrun\033[0m     \033[90m-\033[0m \033[32mRun the container\033[0m"
	@echo "  \033[36mmcp\033[0m     \033[90m-\033[0m \033[32mRun as MCP server (stdio, no tty/volumes)\033[0m"
	@echo "  \033[36mclean\033[0m   \033[90m-\033[0m \033[32mRemove image and prune unused resources\033[0m"
	@echo "  \033[36mdns\033[0m     \033[90m-\033[0m \033[32mConfigure .lab DNS domain (run once, needs sudo)\033[0m"
	@echo "  \033[36mnuke\033[0m    \033[90m-\033[0m \033[32mKill and restart the builder (fixes hangs)\033[0m"
	@echo "  \033[36mpulse\033[0m \033[90m-\033[0m \033[32mTest if builder can complete a build\033[0m"
	@echo "  \033[36mhelp\033[0m    \033[90m-\033[0m \033[32mShow this help message (default)\033[0m"
	@echo ""
	@echo "\033[90mNote: build/run auto-recover if builder is hung ($(HEALTH_TIMEOUT)s timeout)\033[0m"
	@echo ""
