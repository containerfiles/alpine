IMAGE_NAME := $(notdir $(CURDIR))
HOST_DIR := /tmp/container/$(IMAGE_NAME)
TTY_FLAG := --tty
VOLUMES := --volume "$(HOST_DIR):/mnt/shared"
MEMORY := 512M
HEALTH_TIMEOUT := 10
BUILD_TIMEOUT := 120

-include container.conf
-include $(HOME)/Library/Application\ Support/com.containerfiles.$(IMAGE_NAME)/local.conf

.DEFAULT_GOAL := help
.PHONY: status build run mcp stop clean nuke help pulse _pulse _build_check _dns_check

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
	@if ! container system dns list 2>/dev/null | grep -q '^box$$'; then \
		echo "\033[33mSetting up .box DNS domain (first-time setup)...\033[0m"; \
		sudo container system dns create box; \
	fi
	@if [ "$$(container system property get dns.domain 2>/dev/null)" != "box" ]; then \
		container system property set dns.domain box >/dev/null 2>&1; \
	fi
	@if [ ! -f /etc/resolver/containerization.box ]; then \
		echo "\033[33mCreating /etc/resolver/containerization.box...\033[0m"; \
		echo "domain box\nsearch box\nnameserver 127.0.0.1\nport 2053" | sudo tee /etc/resolver/containerization.box >/dev/null; \
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
	@echo "Spawning at \033[36m$(IMAGE_NAME).box\033[0m"
	container run $(strip --remove --name $(IMAGE_NAME) --memory $(MEMORY) --interactive $(TTY_FLAG) $(VOLUMES) $(PORTS) $(ENV_VARS) $(EXTRA_FLAGS)) "$(IMAGE_NAME)"

# ============================================================
# MCP (stdio mode for MCP servers)
# ============================================================
mcp: _pulse _build_check
	@container run $(strip --remove --name $(IMAGE_NAME) --memory $(MEMORY) $(ENV_VARS) $(EXTRA_FLAGS)) "$(IMAGE_NAME)"

# ============================================================
# Stop
# ============================================================
stop:
	@container stop $(IMAGE_NAME) 2>/dev/null && echo "\033[32mStopped.\033[0m" || echo "Not running."

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
	@echo "  \033[36mstatus\033[0m  \033[90m-\033[0m \033[32mShow builder, images, and containers\033[0m"
	@echo "  \033[36mbuild\033[0m   \033[90m-\033[0m \033[32mBuild the container image\033[0m"
	@echo "  \033[36mrun\033[0m     \033[90m-\033[0m \033[32mRun the container (accessible at name.box)\033[0m"
	@echo "  \033[36mmcp\033[0m     \033[90m-\033[0m \033[32mRun as MCP server (stdio, no tty/volumes)\033[0m"
	@echo "  \033[36mstop\033[0m    \033[90m-\033[0m \033[32mStop the running container\033[0m"
	@echo "  \033[36mclean\033[0m   \033[90m-\033[0m \033[32mRemove image and prune unused resources\033[0m"
	@echo "  \033[36mnuke\033[0m    \033[90m-\033[0m \033[32mKill and restart the builder (fixes hangs)\033[0m"
	@echo "  \033[36mpulse\033[0m   \033[90m-\033[0m \033[32mTest if builder is responsive\033[0m"
	@echo "  \033[36mhelp\033[0m    \033[90m-\033[0m \033[32mShow this help message (default)\033[0m"
	@echo ""
	@echo "\033[90mAuto-recovers from builder hangs. Access running containers at <name>.box\033[0m"
	@echo ""
