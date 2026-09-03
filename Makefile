SHELL := /bin/bash

.PHONY: preflight build up down logs ps smoke backup test-vllm test-litellm litellm-create-key litellm-register-vectorstore clean-data

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

test-vllm:
	@test -n "$(SERVICE)" || (echo "Ús: make test-vllm SERVICE=embeddings|reasoning|coding" && exit 1)
	./scripts/test-vllm.sh "$(SERVICE)"

test-litellm:
	@test -n "$(API_KEY)" || (echo "Ús: make test-litellm API_KEY=sk-... [MODEL=nom]" && exit 1)
	LITELLM_API_KEY="$(API_KEY)" ./scripts/test-litellm-api.sh "$(MODEL)"

litellm-create-key:
	@test -n "$(USER)" || (echo "Ús: make litellm-create-key USER=id [BUDGET=usd] [MODELS=m1,m2]" && exit 1)
	./scripts/litellm-create-key.sh "$(USER)" "$(BUDGET)" "$(MODELS)"

litellm-register-vectorstore:
	./scripts/litellm-register-vectorstore.sh "$(NAME)"

clean-data:
	@echo "PERILL: elimina tots els volums nous. Executa manualment: docker compose down -v"
