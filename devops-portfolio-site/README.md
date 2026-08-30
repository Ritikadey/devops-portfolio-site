# DevOps Portfolio Site

A production-style, containerized website deployed on **AWS Free Tier**, provisioned with
**Terraform**, and shipped through **GitHub Actions** — no long-lived AWS keys, no always-on
servers, no surprise bill.

The site itself doubles as the demo: the "Live systems panel" on the homepage calls a real
Lambda + DynamoDB API, and the architecture/pipeline sections describe the actual infrastructure
this repo provisions.

**Live URL:** _add your CloudFront / custom domain URL here once deployed_

---

## Table of contents

- [Architecture](#architecture)
- [Repository structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Local development](#local-development)
- [Deploying from scratch](#deploying-from-scratch)
- [CI/CD pipeline](#cicd-pipeline)
- [Cost breakdown](#cost-breakdown)
- [Security](#security)
- [Monitoring & observability](#monitoring--observability)
- [Design decisions & trade-offs](#design-decisions--trade-offs)
- [Roadmap](#roadmap)
- [Talking points for interviews](#talking-points-for-interviews)

---

## Architecture

```
                     ┌────────────────────┐
        HTTPS        │   CloudFront (CDN)  │        HTTPS
   ┌────────────────▶│  OAC · TLS · cache  │◀───────────────┐
   │                  └──────────┬──────────┘                 │
   │                             │ origin fetch                │
┌──┴───┐                ┌────────▼────────┐           ┌───────┴───────┐
│ Users │                │  S3 bucket       │           │ API Gateway    │
└──┬───┘                │  (private,       │           │  (HTTP API)    │
   │                     │   static assets) │           └───────┬───────┘
   │        fetch()                                              │
   └────────────────────────────────────────────────────────────▶│
                                                                    ▼
                                                          ┌───────────────┐
                                                          │ Lambda         │
                                                          │ (container     │
                                                          │  image, ECR)   │
                                                          └───────┬───────┘
                                                                    │
                                                          ┌───────▼───────┐
                                                          │ DynamoDB       │
                                                          │ (visitor count)│
                                                          └────────────────┘

   ┌────────────────────────────────────────────────────────────────────┐
   │  GitHub Actions (OIDC — no stored AWS keys)                        │
   │  ── deploy-frontend.yml → build (Vite) → sync to S3 → invalidate   │
   │  ── deploy-backend.yml  → build image  → push ECR → update Lambda  │
   │  ── terraform.yml       → plan on PR   → gated apply on main       │
   └────────────────────────────────────────────────────────────────────┘
```

A rendered, interactive version of this diagram is on the live site itself
(`#architecture` section).

**Why this shape:**
- **No EC2, no NAT gateway, no load balancer.** Those are the fastest ways a "Free Tier" AWS
  account starts costing money. Everything here is either fully static (S3/CloudFront) or
  pay-per-request (Lambda, API Gateway, DynamoDB on-demand).
- **The bucket is private.** CloudFront reaches it through an Origin Access Control (OAC) —
  the modern replacement for the older, deprecated Origin Access Identity. There is no public
  S3 website endpoint.
- **The one dynamic feature is intentionally small** — a visitor counter — but it exercises the
  full serverless path (API Gateway → Lambda → DynamoDB) so the project demonstrates more than a
  static site while staying inside the always-free Lambda/DynamoDB tiers.

---

## Repository structure

```
.
├── frontend/                # Vite static site (HTML/CSS/JS, no framework)
│   ├── src/                 # main.js, style.css
│   ├── index.html
│   ├── Dockerfile           # nginx image for local dev / parity testing
│   └── nginx.conf
├── backend/                 # Visitor-counter API
│   ├── src/handler.js       # Lambda handler
│   ├── test/                # node:test unit tests, mocked DynamoDB client
│   └── Dockerfile           # Lambda container image (public.ecr.aws/lambda/nodejs)
├── infra/                   # Terraform — the entire AWS stack
│   ├── bootstrap/           # One-time: S3 state bucket + DynamoDB lock table
│   ├── versions.tf          # Providers + remote state backend
│   ├── frontend.tf          # S3 + CloudFront + OAC (+ optional ACM/Route 53)
│   ├── api.tf                # DynamoDB + ECR + Lambda + API Gateway
│   ├── iam.tf                # Lambda exec role + GitHub OIDC + two scoped deploy roles
│   ├── monitoring.tf         # CloudWatch alarms/dashboard + AWS Budgets alert
│   └── outputs.tf
├── .github/
│   ├── workflows/            # ci.yml, deploy-frontend.yml, deploy-backend.yml,
│   │                         # terraform.yml, codeql.yml
│   └── dependabot.yml
├── docker-compose.yml        # Local full-stack dev (frontend + Lambda RIE)
└── Makefile
```

---

## Prerequisites

- An AWS account (Free Tier eligible)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.7
- [Docker](https://docs.docker.com/get-docker/)
- Node.js 20+
- AWS CLI v2, configured with a profile that has enough access to bootstrap the project
  (see below — after the first apply, day-to-day CI uses narrowly-scoped roles instead)

---

## Local development

```bash
# Frontend only
cd frontend
npm install
npm run dev          # http://localhost:5173

# Backend unit tests
cd backend
npm install
npm test

# Full stack in Docker (frontend nginx container + Lambda RIE for the API)
docker compose up --build
```

The frontend's "Live systems panel" needs `VITE_API_URL` pointed at a real API to show live
data; without it, it shows a clear "not configured" state rather than fake numbers — see
`frontend/.env.example`.

---

## Deploying from scratch

This is a **one-time setup**, done manually with elevated (but still your own) AWS credentials.
After this, GitHub Actions handles every future deploy with narrowly-scoped, short-lived roles.

### 1. Bootstrap Terraform remote state

```bash
cd infra/bootstrap
terraform init
terraform apply -var="project_name=devops-portfolio" -var="aws_region=ap-south-1"
# copy the printed backend_config_snippet output into infra/backend.hcl
```

### 2. First-time chicken-and-egg: push an initial Lambda image

Terraform's `aws_lambda_function` needs an image that already exists in ECR before it can create
the function. Order of operations:

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init -backend-config=backend.hcl

# Create just the ECR repo first
terraform apply -target=aws_ecr_repository.visitor_api

# Build & push a real image
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
docker build -t <account>.dkr.ecr.<region>.amazonaws.com/devops-portfolio/visitor-api:init ./backend
docker push <account>.dkr.ecr.<region>.amazonaws.com/devops-portfolio/visitor-api:init

# Set lambda_image_uri in terraform.tfvars to that image, then apply everything
terraform apply
```

### 3. Wire up GitHub

In the repo's **Settings → Secrets and variables → Actions → Variables**, add:

| Variable | Value (from `terraform output`) |
|---|---|
| `AWS_REGION` | e.g. `ap-south-1` |
| `AWS_DEPLOY_ROLE_ARN` | `github_actions_role_arn` |
| `AWS_TF_APPLY_ROLE_ARN` | ARN of the `terraform_apply` role |
| `S3_BUCKET_NAME` | `s3_bucket_name` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `cloudfront_distribution_id` |
| `CLOUDFRONT_DOMAIN` | `cloudfront_domain_name` |
| `ECR_REPOSITORY` | `devops-portfolio/visitor-api` |
| `LAMBDA_FUNCTION_NAME` | `lambda_function_name` |
| `API_BASE_URL` | `api_base_url` |
| `TF_STATE_BUCKET` / `TF_LOCK_TABLE` | from the bootstrap step |

Then, under **Settings → Environments**, create a `production` environment and add yourself as a
**required reviewer** — this is what turns `terraform apply` and every deploy into a
one-click-approve step instead of fully unattended automation.

### 4. Push

```bash
git push origin main
```

`deploy-frontend.yml` and `deploy-backend.yml` trigger on changes to their own directory;
`terraform.yml` plans on every PR that touches `infra/` and applies (with approval) on merge.

---

## CI/CD pipeline

| Workflow | Trigger | What it does |
|---|---|---|
| `ci.yml` | every PR / push to main | Lint + build frontend, lint + test backend, `docker build` (no push), `terraform fmt/validate` + `tfsec` |
| `deploy-frontend.yml` | push to `main` touching `frontend/**` | Vite build → sync to S3 → CloudFront invalidation → smoke test |
| `deploy-backend.yml` | push to `main` touching `backend/**` | Test → Docker build → push to ECR → `lambda update-function-code` → smoke test `/health` |
| `terraform.yml` | PR (`plan`, commented on the PR) / merge to `main` (gated `apply`) | Provisions/updates the AWS stack |
| `codeql.yml` | push / PR / weekly | Static analysis for the JS codebase |

All AWS authentication uses **GitHub OIDC** (`aws-actions/configure-aws-credentials` with
`role-to-assume`) — there is no AWS access key stored as a GitHub secret anywhere in this repo.

---

## Cost breakdown

| Service | Free Tier allowance | This project's usage | Cost after 12 months |
|---|---|---|---|
| S3 | 5 GB storage, 20k GET/mo | A few MB, low traffic | ~$0.01–0.05/mo |
| CloudFront | 1 TB transfer, 10M requests/mo | Well under limit | ~$0.00–0.10/mo |
| Lambda | 1M requests/mo — **always free**, not just 12 months | A handful of requests/day | $0.00 |
| API Gateway (HTTP API) | 1M requests/mo (12 mo) | Well under limit | ~$0.00–0.05/mo |
| DynamoDB on-demand | 25 GB storage — always free | One item | ~$0.00–0.02/mo |
| ECR | 500 MB-month private storage (12 mo) | One small image (lifecycle policy keeps only 5) | ~$0.10/mo per extra GB |
| Route 53 (optional, off by default) | Not covered by Free Tier | 1 hosted zone if you set `domain_name` | $0.50/mo + registrar |

**Cost guardrail:** `infra/monitoring.tf` provisions an **AWS Budgets** alert (default
threshold $2/month) that emails a warning at 80% actual spend and 100% forecasted spend — so a
misconfiguration gets caught before it becomes a surprise invoice, not after.

Skipping `domain_name` entirely keeps the whole stack at effectively $0/month; the CloudFront
default domain (`*.cloudfront.net`) already serves valid HTTPS.

---

## Security

- **No public S3 bucket.** All public access is blocked at the bucket level; CloudFront reaches
  it only via Origin Access Control with a bucket policy scoped to that one distribution's ARN.
- **No stored AWS credentials.** GitHub Actions authenticates via OIDC federation to two
  separate IAM roles (see below), each with a short-lived session token.
- **Two roles, split by blast radius:**
  - `github-actions` (used by `deploy-frontend.yml` / `deploy-backend.yml`) can only sync to
    the one S3 bucket, invalidate the one CloudFront distribution, push to the one ECR repo,
    and update the one Lambda function's code. It cannot touch IAM.
  - `terraform-apply` (used only by `terraform.yml`, gated behind a required-reviewer
    GitHub Environment) has the broader permissions Terraform needs to provision the stack,
    including managing the two IAM roles above — but nothing else, and it can't be
    assumed from an arbitrary branch.
- **Lambda execution role** is scoped to exactly one DynamoDB table and one log group — not a
  wildcard `dynamodb:*` or `logs:*`.
- **Automated dependency + code scanning:** Dependabot (npm, Docker base images, GitHub
  Actions, Terraform providers) and CodeQL, both free for public repos.
- **IaC scanning:** `tfsec` runs in `ci.yml` on every PR that touches `infra/`.
- **Security headers** on the frontend (`X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`) — set in `nginx.conf` for local parity; for production, the equivalent is a
  CloudFront response headers policy (left as a documented next step, see [Roadmap](#roadmap),
  since it's the one piece not exercised locally).

**Deliberately not included:** AWS WAF and GuardDuty are genuinely good practices but both carry
a recurring charge that doesn't fit a "stay near $0" portfolio project. They're called out here
explicitly because knowing what you *left out and why* is as relevant in an interview as what you
built.

---

## Monitoring & observability

- **CloudWatch dashboard** (`${project_name}-overview`) — Lambda invocations/errors, API Gateway
  request count/latency, CloudFront request volume, all on one page.
- **CloudWatch alarms** → SNS → email for: Lambda errors, Lambda throttles, API Gateway 5xx.
- **Structured API Gateway access logs** (JSON, 14-day retention) for request-level debugging.
- **CI smoke tests** — every deploy workflow curls the live endpoint after deploying and fails
  the run (not just the deploy step) if it doesn't get a healthy response, so a bad deploy is
  caught by the pipeline, not by a person noticing the site is down.

---

## Design decisions & trade-offs

- **Terraform over the AWS Console or raw CloudFormation** — it's the most widely used IaC tool
  in job postings, and its plan/apply model maps cleanly onto the PR-review workflow used here.
- **Vite + vanilla JS over a full frontend framework** — the site is a handful of sections with
  one small dynamic widget; a framework would add build complexity without changing what ships.
- **API Gateway HTTP API over REST API** — cheaper, simpler, and this project doesn't need REST
  API's request/response transformation or usage-plan features.
- **Lambda container image over a .zip deployment** — chosen specifically to exercise Docker +
  ECR in the pipeline, since "Dockerize it" was a project requirement; a .zip package would be
  marginally simpler for this workload alone.
- **Two IAM roles instead of one** — see [Security](#security). The extra Terraform is worth it
  as a demonstration of least-privilege thinking, which is exactly what gets asked about in a
  DevOps interview.

---

## Roadmap

Ideas for extending this project further (intentionally left undone to keep the base project
focused and inside Free Tier — good material for "what would you add next" in an interview):

- CloudFront response headers policy for CSP/HSTS, replacing the nginx-only headers
- Blue/green Lambda deploys using aliases + weighted routing
- A staging environment (`environment = "staging"`) with its own Terraform workspace
- Canary smoke tests via CloudWatch Synthetics (has a small free tier, evaluate before adding)
- Move `.env`-style config to AWS Systems Manager Parameter Store (free tier: standard params)

---

## Talking points for interviews

- Why the bucket is private and how OAC differs from the deprecated OAI
- The chicken-and-egg problem of bootstrapping remote Terraform state, and how it's solved here
- Why there are two separate IAM roles for CI, not one — and what each can and can't do
- How the pipeline authenticates to AWS without ever storing a long-lived access key
- What would need to change to make this multi-environment (staging/prod) or multi-region
- The specific Free Tier limits that would actually matter if traffic grew 100x

---

## License

MIT — see [LICENSE](LICENSE).
