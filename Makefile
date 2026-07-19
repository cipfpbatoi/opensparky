SHELL := /bin/bash

.PHONY: preflight build up down logs ps smoke backup pull-model test-ollama test-api clean-data

preflight:
	./scripts/preflight.sh

build:
	docker compose build --pull

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f --tail=200

ps:
	docker compose ps

smoke:
	./scripts/smoke-test.sh

backup:
	./scripts/backup.sh

pull-model:
	@test -n "$(MODEL)" || (echo "Ús: make pull-model MODEL=nom:model" && exit 1)
	docker compose exec ollama ollama pull "$(MODEL)"

test-ollama:
	./scripts/test-local-ollama.sh "$(MODEL)"

test-api:
	@test -n "$(API_KEY)" || (echo "Ús: make test-api API_KEY=sk-... [MODEL=nom:model]" && exit 1)
	OPENWEBUI_API_KEY="$(API_KEY)" ./scripts/test-openwebui-api.sh "$(MODEL)"

clean-data:
	@echo "PERILL: elimina els dos volums nous. Executa manualment: docker compose down -v"
