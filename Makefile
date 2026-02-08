.PHONY: help init lint format format-fix check clean security security-scan test pre-commit setup ci all

# Default target
.DEFAULT_GOAL := help

# Variables
SCRIPT := create-cloud-template.sh
SHELLCHECK_OPTS := -e SC1090,SC1091
DOCKER_RUN := docker run --rm -v "$(PWD):/work" -w /work
SHELLCHECK_IMAGE := koalaman/shellcheck:stable
SHFMT_IMAGE := mvdan/shfmt:v3.7.0
GITLEAKS_IMAGE := zricethezav/gitleaks:latest
DETECT_SECRETS_IMAGE := python:3.11-slim

help: ## Show this help message
	@echo "Available targets:"
	@echo "  make init          - Install pre-commit hooks"
	@echo "  make security      - Run security scans (Gitleaks + detect-secrets)"
	@echo "  make lint          - Run ShellCheck linting"
	@echo "  make format        - Check shell script formatting"
	@echo "  make format-fix    - Auto-fix shell script formatting"
	@echo "  make check         - Run all checks (security + lint + format)"
	@echo "  make clean         - Remove temporary files"

init: ## Install pre-commit hooks
	@echo "Installing pre-commit hooks..."
	@if ! command -v pre-commit >/dev/null 2>&1; then \
		echo "Error: pre-commit not found. Install it with: pip install pre-commit"; \
		exit 1; \
	fi
	pre-commit install
	pre-commit install --hook-type commit-msg
	@echo "✓ Pre-commit hooks installed"

lint: ## Run ShellCheck on the script
	@echo "Running ShellCheck..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: docker not found. Install Docker to run linting checks."; \
		exit 1; \
	fi
	$(DOCKER_RUN) $(SHELLCHECK_IMAGE) $(SHELLCHECK_OPTS) $(SCRIPT)
	@echo "✓ Linting passed"

format: ## Check shell script formatting
	@echo "Checking script formatting..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: docker not found. Install Docker to run formatting checks."; \
		exit 1; \
	fi
	@$(DOCKER_RUN) $(SHFMT_IMAGE) -i 2 -bn -ci -sr -d $(SCRIPT) || (echo "✗ Formatting issues found. Run 'make format-fix' to fix." && exit 1)
	@echo "✓ Formatting check passed"

format-fix: ## Auto-fix shell script formatting
	@echo "Formatting script..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: docker not found. Install Docker to run formatting."; \
		exit 1; \
	fi
	$(DOCKER_RUN) $(SHFMT_IMAGE) -i 2 -bn -ci -sr -w $(SCRIPT)
	@echo "✓ Formatting complete"

check: security lint format ## Run all checks (security + lint + format)

# Additional targets (not shown in help, but available)
setup: init ## Set up development environment (install hooks)
	@echo "✓ Development environment set up"

clean: ## Clean temporary files
	@echo "Cleaning temporary files..."
	@find . -type f -name "*.bak" -delete
	@find . -type f -name "*.tmp" -delete
	@find . -type f -name "*.swp" -delete
	@find . -type f -name "*~" -delete
	@echo "✓ Clean complete"

security: security-scan ## Run security scans (Gitleaks + detect-secrets)

security-scan: ## Run security scanning (Gitleaks, detect-secrets)
	@echo "Running security scans..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "Error: docker not found. Install Docker to run security scans."; \
		exit 1; \
	fi
	@echo "Running Gitleaks..."
	@$(DOCKER_RUN) $(GITLEAKS_IMAGE) detect --verbose --no-banner --source /work || (echo "⚠ Gitleaks found potential secrets. Review the output above." && exit 1)
	@echo "✓ Gitleaks scan passed"
	@echo "Running detect-secrets..."
	@if [ ! -f .secrets.baseline ]; then \
		echo "Creating .secrets.baseline..."; \
		$(DOCKER_RUN) $(DETECT_SECRETS_IMAGE) sh -c "pip install -q detect-secrets && detect-secrets scan --baseline .secrets.baseline" || true; \
	fi
	@$(DOCKER_RUN) $(DETECT_SECRETS_IMAGE) sh -c "pip install -q detect-secrets && detect-secrets audit .secrets.baseline --report --json" || (echo "⚠ detect-secrets found potential secrets. Review with: detect-secrets audit .secrets.baseline" && exit 1)
	@echo "✓ detect-secrets scan passed"
	@echo "✓ Security scanning complete"

# Additional targets (not shown in help, but available)
test: ## Run syntax and basic tests
	@echo "Running syntax check..."
	@bash -n $(SCRIPT) || (echo "✗ Syntax check failed" && exit 1)
	@echo "✓ Syntax check passed"
	@echo "Testing help output..."
	@./$(SCRIPT) --help > /dev/null 2>&1 || (echo "✗ Help test failed" && exit 1)
	@echo "✓ Help test passed"
	@echo "Testing invalid option handling..."
	@./$(SCRIPT) --invalid-option 2>&1 | grep -q "Unknown option" || (echo "✗ Invalid option test failed" && exit 1)
	@echo "✓ Invalid option test passed"

pre-commit: ## Run pre-commit hooks on all files
	@echo "Running pre-commit hooks..."
	@if ! command -v pre-commit >/dev/null 2>&1; then \
		echo "Error: pre-commit not found. Install it with: pip install pre-commit"; \
		exit 1; \
	fi
	pre-commit run --all-files

ci: lint test ## Run CI checks (for GitHub Actions)

all: check test ## Run all checks, validations, and security scans
