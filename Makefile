# =====================================================================
# PulseID — Development Makefile
# =====================================================================
#
# Foundation commands for the PulseID monorepo.
#
# NOTE: Application code has not been implemented yet. Commands for the
# backend, web, and mobile apps report that the component is not yet
# initialized. They will become functional in later phases.
# =====================================================================

SHELL := /bin/bash

.PHONY: help setup backend web mobile test lint format docker-up docker-down \
        clean

help: ## Show this help message
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## Bootstrap the local development environment
	@echo "==> 📦 Setting up PulseID development environment..."
	@echo ""
	@echo "    Copy .env.example to .env and fill in your config:"
	@echo "      cp .env.example .env"
	@echo ""
	@echo "    Component setup will be added here as each app is scaffolded"
	@echo "    (backend: Python venv + deps, web/mobile: npm install)."

backend: ## Run the Django backend
	@echo "==> 🐍 Backend is not initialized yet."
	@echo "    The Django project will be scaffolded in Phase 2. Coming soon."

web: ## Run the admin web app (React + Vite)
	@echo "==> 🌐 Web app is not initialized yet."
	@echo "    The React + Vite admin app will be scaffolded in Phase 5. Coming soon."

mobile: ## Run the mobile app (Expo / React Native)
	@echo "==> 📱 Mobile app is not initialized yet."
	@echo "    The Expo app will be scaffolded in Phase 6. Coming soon."

test: ## Run all tests (backend + web + mobile)
	@echo "==> 🧪 No test suites exist yet."
	@echo "    Tests will run here once the backend (pytest) and"
	@echo "    web/mobile (vitest/jest) apps are scaffolded."
	@echo ""
	@echo "    This target will run:"
	@echo "      backend: pytest backend/"
	@echo "      web:     npm test --workspace=web"
	@echo "      mobile:  npm test --workspace=mobile"

lint: ## Lint all code (ruff, eslint, tsc)
	@echo "==> 🔍 No code to lint yet."
	@echo "    Linting will run here once apps are scaffolded."
	@echo ""
	@echo "    This target will run:"
	@echo "      backend: ruff check backend/"
	@echo "      web:     npm run lint --workspace=web"
	@echo "      mobile:  npm run lint --workspace=mobile"

format: ## Format all code (black/ruff format, prettier)
	@echo "==> ✨ No code to format yet."
	@echo "    Formatting will run here once apps are scaffolded."
	@echo ""
	@echo "    This target will run:"
	@echo "      backend: ruff format backend/"
	@echo "      web:     prettier --write web/"
	@echo "      mobile:  prettier --write mobile/"

docker-up: ## Start the local dev infrastructure (PostgreSQL, Redis, Celery)
	@echo "==> 🐳 Dockerized services are not defined yet."
	@echo "    docker-compose.yml will be added in infra/ during Phase 2."
	@echo ""
	@echo "    This target will start: postgres, redis, celery-worker, celery-beat"

docker-down: ## Stop the local dev infrastructure
	@echo "==> 🐳 No docker-compose services to stop yet (added in Phase 2)."

clean: ## Remove build artifacts, caches, and generated files
	@echo "==> 🧹 Cleaning generated artifacts..."
	@find . -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".ruff_cache" -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "node_modules" -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".expo" -prune -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "dist" -prune -exec rm -rf {} + 2>/dev/null || true
	@echo "   Done."