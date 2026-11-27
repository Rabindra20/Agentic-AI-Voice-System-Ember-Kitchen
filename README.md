# Ember Kitchen — Agentic AI Voice System (DINEAI)

**Workshop:** Agentic AI Enablement | **Domain:** Restaurant / Catering | **AI Persona:** DINEAI

---

## Architecture

```
Caller
  │
  ▼
Amazon Connect  (hours check → off-hours message or proceed)
  │
  ▼
Amazon Lex V2  (intent classification, Polly NTTS Joanna voice)
  │
  ▼
Bedrock AgentCore Runtime  ◄──►  Bedrock Guardrails
  (DINEAI Docker container — Claude Haiku reasoning loop)
  ├── AgentCore Gateway (MCP) ──► Lambda tools (8 functions)
  ├── RAG: Embedding Lambda ──► Qdrant on EC2 t3.micro
  └── DynamoDB (Reservations + CallLog)
  │
  ▼
Connect Cases (auto-created on every escalation)
  │
  ▼
Amazon Connect Queues
  GeneralQueue | EmergencyQueue
```

---

## Layer Compliance Checklist

### Layer 1 — Amazon Connect Foundation

| Requirement | Status | Notes |
|-------------|--------|-------|
| Phone system with business hours | ✅ | `terraform/modules/connect/main.tf` |
| Operating hours: Tue–Sun 10:00–22:00, closed Monday | ✅ | Fixed — Monday removed; all open days 10:00–22:00 Europe/London |
| Off-hours graceful handling | ✅ | Plays voice message with correct hours, then disconnects |
| Two queues: General + Emergency | ✅ | `GeneralQueue`, `EmergencyQueue` |
| Contact flow | ✅ | `<prefix>-MainFlow` |
| `<your-name>-EmberKitchen` prefix on all resources | ✅ | Set via `your_name` in `terraform/terraform.tfvars` |

### Layer 2 — NLU (Amazon Lex V2)

| Requirement | Status | Notes |
|-------------|--------|-------|
| Intents for all guest actions | ✅ | 9 intents (see table below) |
| EmergencyEscalation = zero slots | ✅ | No slot definitions on this intent |
| Contact flow branches on Complete / Escalate / EscalateEmergency | ✅ | Conditional routing in MainFlow |
| Polly NTTS voice | ✅ | Joanna, neural engine |

**Intents:**

| Intent | Utterance Examples |
|--------|--------------------|
| CheckAvailability | "Is there availability on Saturday?" |
| MakeReservation | "Book a table for 2 on Friday at 7pm" |
| ModifyReservation | "Change my booking to 4 people" |
| CancelReservation | "Cancel my reservation" |
| DietaryRequirements | "I'm allergic to nuts" |
| CateringEnquiry | "How much does catering cost for 30 people?" |
| PolicyQuestion | "What is your cancellation policy?" |
| Escalate | "I want to speak to a manager" |
| EmergencyEscalation | "Someone is having an allergic reaction!" |

### Layer 3 — Agent Runtime (AgentCore Runtime)

| Requirement | Status | Notes |
|-------------|--------|-------|
| DINEAI built as Docker image | ✅ | `docker/agent/` |
| Agent loop, system prompt, tool-calling logic in container | ✅ | `docker/agent/agent.py` |
| Lambda tools exposed through AgentCore Gateway (MCP) | ✅ | `_mcp_call()` with SigV4; `AGENTCORE_GATEWAY_ENDPOINT` injected by Terraform into agent Lambda env |
| Greet caller by name on first turn | ✅ | `guest_name` from session attributes |
| After update, verify DynamoDB record (not from DINEAI response) | ✅ | System prompt instructs `verify_booking` after every update |
| All 8 required tools implemented | ✅ | See tool catalogue below |

**Tool Catalogue:**

| Tool | Lambda Handler | Key Inputs | Purpose |
|------|---------------|-----------|---------|
| `verify_booking` | `tools.verify_booking` | `guest_phone` | Looks up reservations by phone (GSI query) |
| `check_table_availability` | `tools.check_table_availability` | `date`, `time`, `party_size` | Checks remaining covers for a slot |
| `book_table` | `tools.book_table` | `guest_name`, `guest_phone`, `date`, `time`, `party_size` | Creates reservation; returns `reservation_id` |
| `modify_reservation` | `tools.modify_reservation` | `reservation_id`, fields… | Updates specified fields |
| `cancel_reservation` | `tools.cancel_reservation` | `reservation_id` | Sets status = cancelled |
| `record_dietary_requirements` | `tools.record_dietary_requirements` | `reservation_id`, `dietary_requirements[]` | Updates dietary list |
| `request_catering_quote` | `tools.request_catering_quote` | `guests`, `package` | Returns estimate (standard £45, premium £75, luxury £120) |
| `log_call_outcome` | `tools.log_call_outcome` | `intent`, `outcome`, `escalation_reason` | Writes CallLog; creates Connect Case if escalation |

### Layer 4 — Self-Hosted RAG

| Requirement | Status | Notes |
|-------------|--------|-------|
| Vector DB on EC2 t3.micro | ✅ | Qdrant in Docker, bootstrapped via user-data |
| Embedding model as Lambda container image | ✅ | `BAAI/bge-small-en-v1.5`, `docker/embedding/` |
| Six policy documents indexed | ✅ | `scripts/index_policies.py` |
| Retrieval wired into agent | ✅ | `retrieve_policy` tool in agent loop |
| Differently-worded query returns correct document | ✅ | Synonym expansion fix in `embedding_handler._query()` |

**Policy documents indexed:**
- `ember_kitchen_general_info`
- `reservation_policy`
- `dietary_and_allergen_menu`
- `catering_packages_and_pricing`
- `private_dining_and_events_policy`
- `allergy_emergency_procedures`

### Layer 5 — Guardrails and Escalation

| Requirement | Status | Notes |
|-------------|--------|-------|
| Bedrock Guardrails with 3 denied topics | ✅ | MedicalAdvice, CompetitorComparison, InternalKitchenDetails |
| Guardrail linked to agent | ✅ | Applied via `guardrailIdentifier` / `guardrailVersion` at `invoke_model` API level |
| System prompt contains same denied topic rules | ✅ | `docker/agent/agent.py` system prompt |
| Denied-topic blocked on live test call | 📋 | Demonstrate during evaluation (Scenario #12 and #13) |
| Every escalation auto-creates Connect Case | ✅ | `log_call_outcome` Lambda calls `connectcases.create_case()` |
| Connect Case fields: guest name, intent, escalation reason | ✅ | All three fields written to case |

### Layer 6 — Observability

| Requirement | Status | Notes |
|-------------|--------|-------|
| Per-execution trace for any single call | ✅ | X-Ray active tracing on all Lambdas; X-Ray group `<prefix>-DINEAI` |
| At least one alarm triggered on test condition | ✅ | Per-Lambda error alarm (threshold = 1 error / 60 s) |
| Per-call token cost visible separately from billing | ✅ | `TOKEN_COST` log pattern → CloudWatch metric `EmberKitchen/DINEAI/PerCallTokenCostUSD` |

### Layer 7 — Evaluation

| Requirement | Status | Notes |
|-------------|--------|-------|
| At least 15 test scenarios | ✅ | 17 scenarios in `docs/evaluation/test_scenarios.md` |
| Covers: routine, multi-tool, RAG, denied topic, emergency, unverified, tool failure | ✅ | All categories covered |
| Pass rate defined and reported | ✅ | 17/17 = 100% after fix |
| One documented failure: root cause + fix + pass rate after | ✅ | Scenario #10 — informal cancellation phrasing; synonym expansion fix |

---

## Models

| Role | Model | Justification |
|------|-------|---------------|
| Reasoning | Claude Haiku (`anthropic.claude-haiku-20240307-v1:0`) | Default per spec; lowest-cost Anthropic model on Bedrock |
| TTS | Amazon Polly NTTS — Joanna voice | Lowest-cost NTTS; configured directly on Lex V2 bot locale; no Nova Sonic needed |
| Embeddings | `BAAI/bge-small-en-v1.5` (self-hosted Lambda container) | Free to run; 384-dim; fits t3.micro Qdrant; ~130 MB image |

**Two distinct models used** — reasoning and TTS are separate as required.

---

## Prohibited Services (not used)

| Not Allowed | Why Not Used |
|-------------|-------------|
| Q in Connect AI Agent | Replaced by AgentCore Runtime (Docker container) |
| Amazon Titan Embeddings | Self-hosted `bge-small-en-v1.5` used instead |
| Amazon OpenSearch | Qdrant on EC2 t3.micro used instead |
| S3 / Knowledge Base | Qdrant vector DB replaces this entirely |
| Same model for reasoning and TTS | Claude Haiku (reasoning) + Polly NTTS (TTS) — two distinct models |

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.6.0
- Docker Desktop (running)
- Python 3.12+ (for `scripts/index_policies.py`)
- An EC2 key pair in your target region

---

## Deployment — Step by Step

### 1. Set your name in tfvars

Edit `terraform/terraform.tfvars`:
```
your_name = "rabindra"
```

Account ID and region are resolved automatically from your active AWS credentials via `data "aws_caller_identity"` and `data "aws_region"` — no hardcoding needed.

### 2. Login to ECR and build Docker images

```bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

bash scripts/build_and_push.sh $ACCOUNT $REGION rabindra
```

### 3. Terraform init → validate → plan → apply

```bash
# Using run.sh (recommended)
./run.sh init dev
./run.sh validate
./run.sh plan dev
./run.sh apply dev

# Or directly
cd terraform
terraform init
terraform plan
terraform apply
```

### 4. Fix the Lex alias ARN (two-pass deploy — required)

```bash
cd terraform
terraform output lex_bot_alias_arn
```

Copy the ARN. Open `terraform/modules/connect/main.tf` and replace `PLACEHOLDER_LEX_ALIAS_ARN` with it. Then re-apply:

```bash
./run.sh apply dev
```

### 5. Index policy documents into Qdrant

```bash
python scripts/index_policies.py \
  --function-name rabindra-EmberKitchen-demo-embedding \
  --region us-east-1
```

### 6. Claim a phone number (manual — AWS Console)

AWS Console → Amazon Connect → your instance → Phone numbers → **Claim a number** → assign to `rabindra-EmberKitchen-demo-MainFlow`.

### 7. Test

Dial the claimed number. DINEAI will answer.

---

## Cost Controls

```bash
# Stop Qdrant EC2 when not testing
aws ec2 stop-instances --instance-ids $(cd terraform && terraform output qdrant_instance_id)

# Start again before next test session
aws ec2 start-instances --instance-ids $(cd terraform && terraform output qdrant_instance_id)
```

- **Claude Haiku** — do not switch to Sonnet/Opus without written justification
- **Polly NTTS** — do not switch to Nova Sonic without written justification
- **Budget cap: $30** — monitor in AWS Cost Explorer; provide screenshot at submission

---

## Resource Naming

All resources use the `<your_name>-EmberKitchen-demo` prefix.
Set `your_name` in `terraform/terraform.tfvars`.

---

## Repository Structure

```
├── docker/
│   ├── agent/                  # DINEAI agent container (Claude Haiku loop)
│   │   ├── Dockerfile
│   │   ├── agent.py
│   │   └── requirements.txt
│   └── embedding/              # bge-small-en-v1.5 embedding Lambda container
│       ├── Dockerfile
│       ├── embedding_handler.py
│       └── requirements.txt
├── docs/
│   ├── evaluation/
│   │   └── test_scenarios.md   # 17 test scenarios + results
│   └── policies/               # Six Ember Kitchen policy documents (RAG source)
├── scripts/
│   ├── build_and_push.sh       # Build + push both Docker images to ECR
│   └── index_policies.py       # Index policy docs into Qdrant via embedding Lambda
├── terraform/
│   ├── main.tf                 # Root module — wires all modules together
│   ├── terraform.tfvars        # Set your_name here
│   ├── run.sh → ../run.sh      # Use run.sh <init|plan|apply|validate|clean> <env>
│   └── modules/
│       ├── connect/            # Amazon Connect instance, hours, queues, flow, Cases
│       ├── lex/                # Lex V2 bot, 9 intents, Polly NTTS voice
│       ├── agentcore/          # Bedrock Agent (DINEAI), action groups, IAM
│       ├── lambda/             # 8 tool Lambdas + embedding Lambda
│       ├── dynamodb/           # Reservations table (GSI) + CallLog table
│       ├── guardrails/         # Bedrock Guardrail — 3 denied topics + PII
│       ├── rag/                # EC2 t3.micro (Qdrant) + security group
│       └── observability/      # CloudWatch alarms, X-Ray group, token cost metric
└── run.sh                      # Terraform wrapper: init/plan/apply/validate/clean
```
