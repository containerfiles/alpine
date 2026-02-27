BIN_NAME := $(notdir $(CURDIR))
IMAGE_NAME := cf-$(BIN_NAME)
HOST_DIR := /tmp/container/$(BIN_NAME)
TTY_FLAG := --tty
VOLUMES := --volume "$(HOST_DIR):/mnt/shared"
HEALTH_TIMEOUT := 10
BUILD_TIMEOUT := 120

-include container.conf

BIN_DIR := /usr/local/bin

.DEFAULT_GOAL := help
.PHONY: status build run mcp stop clean help pulse cast install uninstall health _pulse _build_check

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
		echo "\033[31mBuilder not responding\033[0m"; \
		exit 1; \
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
# Cast (standalone binary)
# ============================================================
cast: _pulse _build_check
	@echo "Casting $(BIN_NAME)..."
	@container-cast cast . --image "$(IMAGE_NAME)" -it -o $(BIN_NAME)
	@echo "\033[32mCast complete!\033[0m"

# ============================================================
# Install (copy cast binary to /usr/local/bin)
# ============================================================
install: cast
	@mkdir -p $(BIN_DIR)
	@if [ -f $(BIN_DIR)/$(BIN_NAME) ]; then rm $(BIN_DIR)/$(BIN_NAME); fi
	@cp $(BIN_NAME) $(BIN_DIR)/$(BIN_NAME)
	@rm -f $(BIN_NAME)
	@echo "\033[32mInstalled $(BIN_NAME) to $(BIN_DIR)\033[0m"

# ============================================================
# Uninstall
# ============================================================
uninstall:
	@if [ -f $(BIN_DIR)/$(BIN_NAME) ]; then \
		rm $(BIN_DIR)/$(BIN_NAME); \
		echo "\033[32mRemoved $(BIN_DIR)/$(BIN_NAME)\033[0m"; \
	else \
		echo "\033[33m$(BIN_NAME) not installed\033[0m"; \
	fi

# ============================================================
# Health
# ============================================================
health:
	@if [ -x $(BIN_DIR)/$(BIN_NAME) ]; then \
		echo "\033[32m$(BIN_NAME) installed\033[0m"; \
	else \
		echo "\033[33m$(BIN_NAME) not installed\033[0m"; \
		exit 1; \
	fi

# ============================================================
# Run
# ============================================================
run: _pulse _build_check
	@mkdir -p "$(HOST_DIR)"
	container run $(strip --remove --name $(BIN_NAME) --interactive $(TTY_FLAG) $(VOLUMES) $(PORTS) $(ENV_VARS) $(EXTRA_FLAGS)) "$(IMAGE_NAME)"

# ============================================================
# MCP (stdio mode for MCP servers)
# ============================================================
mcp: _pulse _build_check
	@container run $(strip --remove --name $(BIN_NAME) $(ENV_VARS) $(EXTRA_FLAGS)) "$(IMAGE_NAME)"

# ============================================================
# Stop
# ============================================================
stop:
	@echo "Single containers exit with Ctrl+C"
	@echo "To force stop: container stop $(BIN_NAME)"

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
# Help
# ============================================================
help:
	@echo ""
	@echo "\033[1mUsage:\033[0m make \033[36m[target]\033[0m"
	@echo ""
	@echo "\033[33mTargets:\033[0m"
	@echo "  \033[36mstatus\033[0m     \033[90m-\033[0m \033[32mShow builder, images, and containers\033[0m"
	@echo "  \033[36mbuild\033[0m      \033[90m-\033[0m \033[32mBuild the container image\033[0m"
	@echo "  \033[36mcast\033[0m       \033[90m-\033[0m \033[32mCast into a standalone binary\033[0m"
	@echo "  \033[36minstall\033[0m    \033[90m-\033[0m \033[32mCast and install to /usr/local/bin\033[0m"
	@echo "  \033[36muninstall\033[0m  \033[90m-\033[0m \033[32mRemove from /usr/local/bin\033[0m"
	@echo "  \033[36mhealth\033[0m     \033[90m-\033[0m \033[32mCheck if binary is installed\033[0m"
	@echo "  \033[36mrun\033[0m        \033[90m-\033[0m \033[32mRun the container\033[0m"
	@echo "  \033[36mmcp\033[0m        \033[90m-\033[0m \033[32mRun as MCP server (stdio, no tty/volumes)\033[0m"
	@echo "  \033[36mclean\033[0m      \033[90m-\033[0m \033[32mRemove image and prune unused resources\033[0m"
	@echo "  \033[36mpulse\033[0m      \033[90m-\033[0m \033[32mTest if builder is responsive\033[0m"
	@echo "  \033[36mhelp\033[0m       \033[90m-\033[0m \033[32mShow this help message (default)\033[0m"
	@echo ""
