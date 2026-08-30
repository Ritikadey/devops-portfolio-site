.PHONY: dev build test lint fmt tf-init tf-plan tf-apply compose-up compose-down

dev:            ## Run the frontend dev server
	cd frontend && npm run dev

build:          ## Build the frontend for production
	cd frontend && npm run build

test:           ## Run backend unit tests
	cd backend && npm test

lint:           ## Lint frontend + backend
	cd frontend && npm run lint
	cd backend && npm run lint

fmt:             ## Format Terraform
	cd infra && terraform fmt -recursive

tf-init:         ## Initialize Terraform (after bootstrap/ has been applied once)
	cd infra && terraform init -backend-config=backend.hcl

tf-plan:         ## Show planned infrastructure changes
	cd infra && terraform plan

tf-apply:        ## Apply infrastructure changes
	cd infra && terraform apply

compose-up:      ## Run the full stack locally in Docker
	docker compose up --build

compose-down:    ## Tear down the local Docker stack
	docker compose down -v
