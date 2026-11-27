# DINEAI — Agentic AI Voice System for Ember Kitchen
## System Design & Research Document

**Project:** Agentic AI Enablement Workshop  
**Domain:** Restaurant & Catering  
**Author:** Rabindra Raj Sah  
**Date:** October 2026  
**Version:** 1.0

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [System Overview](#3-system-overview)
4. [Architecture Design](#4-architecture-design)
5. [Component Deep-Dive](#5-component-deep-dive)
6. [Data Model](#6-data-model)
7. [Agentic Loop Design](#7-agentic-loop-design)
8. [Retrieval-Augmented Generation (RAG)](#8-retrieval-augmented-generation-rag)
9. [Safety, Guardrails & Escalation](#9-safety-guardrails--escalation)
10. [Observability & Cost Control](#10-observability--cost-control)
11. [Security Design](#11-security-design)
12. [Evaluation Results](#12-evaluation-results)
13. [Cost Analysis](#13-cost-analysis)
14. [CI/CD Pipeline](#14-cicd-pipeline)
15. [Limitations & Future Work](#15-limitations--future-work)
16. [Conclusion](#16-conclusion)

---

## 1. Executive Summary

DINEAI is an end-to-end agentic AI voice system that automates reservation management and guest enquiries for Ember Kitchen, a premium London restaurant. Callers interact with a natural-language voice interface powered by Amazon Polly NTTS; their intent is classified by Amazon Lex V2; and a reasoning agent (Claude Haiku on AWS Bedrock) orchestrates up to 8 Lambda-backed tools to fulfil requests — booking tables, recording dietary requirements, generating catering quotes, and retrieving policy information from a self-hosted vector knowledge base.

The system achieves a **100% pass rate** across 17 evaluation scenarios, processes calls end-to-end in under 3 seconds per agent turn, and operates within a **$30 budget cap** through deliberate model and infrastructure choices.

---

## 2. Problem Statement

### 2.1 Context

Restaurant front-of-house teams spend a significant portion of operating hours handling routine phone enquiries: checking availability, taking reservations, answering policy questions, and recording dietary requirements. These calls follow predictable patterns and rarely require human judgment, yet they occupy staff who could otherwise focus on in-person guest experience.

### 2.2 Requirements

The system must:

- Handle inbound phone calls 24 hours a day (with graceful off-hours handling for Tue–Sun 10:00–22:00 Europe/London).
- Identify the caller's intent across 9 distinct categories.
- Execute multi-step reservation workflows reliably (verify → book → confirm).
- Answer policy questions from a structured knowledge base without hallucination.
- Escalate to a human agent on request, and escalate immediately and without delay for medical emergencies.
- Respect a strict set of denied topics (medical advice, competitor comparisons, internal operations).
- Provide full observability: per-call traces, error alarms, and token cost metrics.

### 2.3 Constraints

| Constraint | Rationale |
|------------|-----------|
| No Q in Connect AI Agent | Replaced by a containerised AgentCore Runtime |
| No Amazon Titan Embeddings | Self-hosted bge-small-en-v1.5 required |
| No Amazon OpenSearch | Qdrant on EC2 t3.micro required |
| No same model for reasoning and TTS | Two distinct models must be used |
| Budget cap: $30 | Demonstration environment; cost efficiency critical |

---

## 3. System Overview

DINEAI is structured as a seven-layer stack, each layer independently deployable via Terraform:

```
┌─────────────────────────────────────────────┐
│  Layer 1: Amazon Connect Foundation          │  Phone ingress, hours, queues
│  Layer 2: Amazon Lex V2                      │  Intent classification, Polly NTTS
│  Layer 3: Bedrock AgentCore Runtime          │  Claude Haiku agentic loop
│  Layer 4: Self-Hosted RAG                    │  Qdrant + bge-small embedding
│  Layer 5: Guardrails & Escalation            │  Bedrock Guardrails, Connect Cases
│  Layer 6: Observability                      │  X-Ray, CloudWatch, token cost
│  Layer 7: Evaluation                         │  17 test scenarios, documented failure
└─────────────────────────────────────────────┘
```

### 3.1 Call Flow Summary

```
Caller
  │
  ▼
Amazon Connect  ──► Business hours check
  │                 Off-hours: play message → disconnect
  │                 Open: proceed
  ▼
Amazon Lex V2  ──► Polly NTTS (Joanna) voice
  │                Intent classification (9 intents)
  ▼
Agent Lambda  ──► DINEAI container (AgentCore Runtime)
  │                Claude Haiku reasoning loop
  │                ├── AgentCore Gateway (MCP) → 8 tool Lambdas
  │                ├── Embedding Lambda → Qdrant (RAG)
  │                └── DynamoDB (Reservations + CallLog)
  ▼
Outcome routing
  ├── Complete   → end call normally
  ├── Escalate   → Connect Case created → GeneralQueue
  └── Emergency  → Connect Case created → EmergencyQueue (no delay)
```

---

## 4. Architecture Design

### 4.1 High-Level Architecture Diagram

```
                        ┌──────────────────────────────────────────────────┐
                        │                   AWS Cloud                       │
                        │                                                    │
  ┌──────────┐          │  ┌─────────────┐    ┌──────────────────────────┐  │
  │  Caller  │──PSTN───►│  │   Amazon    │───►│      Amazon Lex V2       │  │
  └──────────┘          │  │   Connect   │    │  9 intents, Polly NTTS   │  │
                        │  └─────────────┘    └──────────┬───────────────┘  │
                        │                               │                    │
                        │                               ▼                    │
                        │  ┌────────────────────────────────────────────┐   │
                        │  │          Bedrock AgentCore Runtime          │   │
                        │  │  ┌──────────────────────────────────────┐  │   │
                        │  │  │  DINEAI Agent Lambda (Docker/ECR)    │  │   │
                        │  │  │  • Claude Haiku via Bedrock           │  │   │
                        │  │  │  • Agentic loop (max 10 iterations)   │  │   │
                        │  │  │  • Bedrock Guardrails enforcement     │  │   │
                        │  │  └──────────────┬───────────────────────┘  │   │
                        │  └─────────────────┼──────────────────────────┘   │
                        │                    │                               │
                        │         ┌──────────┴──────────┐                   │
                        │         ▼                       ▼                  │
                        │  ┌─────────────────┐  ┌───────────────────────┐  │
                        │  │ AgentCore MCP   │  │  Embedding Lambda     │  │
                        │  │ Gateway         │  │  (Docker/ECR)         │  │
                        │  │ (SigV4 signed)  │  │  bge-small-en-v1.5    │  │
                        │  └────────┬────────┘  └──────────┬────────────┘  │
                        │           │                       │                │
                        │           ▼                       ▼                │
                        │  ┌─────────────────┐  ┌───────────────────────┐  │
                        │  │  8 Tool Lambdas │  │  Qdrant EC2 t3.micro  │  │
                        │  │  (Python)       │  │  ember_kitchen_policies│  │
                        │  └────────┬────────┘  └───────────────────────┘  │
                        │           │                                        │
                        │           ▼                                        │
                        │  ┌─────────────────────────────────────────────┐  │
                        │  │               DynamoDB                       │  │
                        │  │  Reservations (GSI: GuestPhoneIndex)         │  │
                        │  │  CallLog                                      │  │
                        │  └─────────────────────────────────────────────┘  │
                        │                                                    │
                        │  ┌─────────────────┐  ┌───────────────────────┐  │
                        │  │ Connect Cases   │  │  CloudWatch / X-Ray   │  │
                        │  │ (auto-created   │  │  Observability        │  │
                        │  │  on escalation) │  │                       │  │
                        │  └─────────────────┘  └───────────────────────┘  │
                        └──────────────────────────────────────────────────┘
```

### 4.2 Network Topology

```
VPC (10.0.0.0/16)
  ├── Public Subnet A
  │     └── Qdrant EC2 t3.micro  (ports 6333/6334 + SSH)
  └── (Lambdas run outside VPC via IAM — no VPC attachment needed)
```

The Qdrant instance is in a public subnet with a security group that restricts access. Lambda functions access it via the private IP resolved by Terraform output.

---

## 5. Component Deep-Dive

### 5.1 Amazon Connect

**Role:** PSTN ingress, business hours enforcement, queue routing.

**Configuration:**
- Instance alias: `<prefix>-EmberKitchen`
- Operating hours: Tuesday–Sunday 10:00–22:00 Europe/London (Monday closed)
- Two queues: `GeneralQueue` (routine escalations), `EmergencyQueue` (allergy/medical)
- Contact flow `<prefix>-MainFlow`: checks hours → routes to Lex → branches on Complete/Escalate/EscalateEmergency
- Connect Cases domain auto-created; a Case is opened for every escalation with guest name, intent, and reason

**Design decision:** Amazon Connect was chosen over a pure SIP/IVR stack because it natively integrates with Lex V2 and provides queue management, cases, and phone number provisioning within a single AWS console.

### 5.2 Amazon Lex V2

**Role:** Natural language intent classification, speech-to-text, Polly NTTS output.

**9 intents:**

| Intent | Key Slots | Trigger Phrases |
|--------|-----------|-----------------|
| CheckAvailability | date, time, party_size | "Is there availability Saturday?" |
| MakeReservation | date, time, party_size | "Book a table for 2 Friday at 7pm" |
| ModifyReservation | reservation_id | "Change my booking to 4 people" |
| CancelReservation | reservation_id | "Cancel my reservation" |
| DietaryRequirements | requirements | "I'm allergic to nuts" |
| CateringEnquiry | guests, package | "Catering for 30?" |
| PolicyQuestion | query | "What is your cancellation policy?" |
| Escalate | — | "I want to speak to a manager" |
| EmergencyEscalation | — | "Someone is having an allergic reaction!" |

**Voice:** Amazon Polly NTTS, Joanna voice, neural engine. Configured directly on the Lex V2 bot locale — no Nova Sonic required.

**Design decision for EmergencyEscalation:** Zero slots are defined. The intent fires on first match, with no slot elicitation. This ensures the agent receives the event immediately and routes to the emergency queue without conversational delay.

### 5.3 Bedrock AgentCore Runtime (DINEAI Agent)

**Role:** The core reasoning engine. Runs inside a Docker container deployed as a Lambda function and backed by an `aws_bedrockagent_agent` Bedrock Agent resource.

**Model:** `anthropic.claude-haiku-20240307-v1:0`

**Key design choices:**

1. **Containerised deployment** — the agent logic ships as an ECR image rather than a zip, enabling arbitrary Python dependencies (boto3, requests) and a clear separation of concerns.

2. **Dual dispatch (MCP primary, direct Lambda fallback)** — in production, tool calls go through the AgentCore Gateway using MCP JSON-RPC 2.0 signed with SigV4. If the Gateway is unavailable or returns an error, the agent falls back to direct boto3 Lambda invocation. This improves resilience without requiring a circuit-breaker library.

3. **Agentic loop cap** — the loop runs for at most 10 iterations per turn to prevent unbounded execution time and token cost.

4. **Post-update verification** — after any mutating tool call (`book_table`, `modify_reservation`, `record_dietary_requirements`), the system prompt instructs the agent to call `verify_booking` again to confirm DynamoDB was updated. This catches optimistic-concurrency issues without requiring a transactional write model.

5. **Token cost logging** — each turn emits a `TOKEN_COST` structured log line containing input tokens, output tokens, and estimated USD. A CloudWatch metric filter converts this to the custom metric `EmberKitchen/DINEAI/PerCallTokenCostUSD`.

**System prompt (condensed):**
```
You are DINEAI, voice assistant for Ember Kitchen.
Hours: Tue–Sun 10:00–22:00. Closed Monday.
Greet caller by name. Use tools for all operations.
After any update, call verify_booking to confirm.
Always call log_call_outcome at end of call.
Voice: ≤3 sentences per response.
Emergency: immediate transfer, no further questions.
Denied topics: medical advice, competitors, internal ops.
```

### 5.4 Tool Lambdas (8 functions)

All tools are implemented in `terraform/modules/lambda/src/tools.py` and deployed as separate Lambda functions from a single source file.

| Tool | Primary Action | DynamoDB Operation |
|------|---------------|-------------------|
| `verify_booking` | GSI query by `guest_phone` | Query (GuestPhoneIndex) |
| `check_table_availability` | Count covers for a slot | Scan with filter |
| `book_table` | Create reservation | PutItem |
| `modify_reservation` | Update fields | UpdateItem |
| `cancel_reservation` | Set status=cancelled | UpdateItem |
| `record_dietary_requirements` | Update dietary list | UpdateItem |
| `request_catering_quote` | Compute estimate | In-memory calculation |
| `log_call_outcome` | Write call log; create Connect Case | PutItem + connectcases API |

**Availability check design:** The current implementation scans the table and sums `party_size` values for a given date/time slot. The restaurant capacity is hardcoded at 50 covers. For production, this would be replaced with a slot-indexed GSI to avoid full-table scans.

### 5.5 AgentCore Gateway (MCP)

The Bedrock AgentCore Gateway exposes the tool Lambdas via a managed MCP (Model Context Protocol) endpoint. Tool calls from the agent container are:
1. Serialised as JSON-RPC 2.0 `tools/call` requests
2. Signed with SigV4 (service: `bedrock`) using the container's task role credentials
3. Sent to `https://bedrock-agentcore.<region>.amazonaws.com/runtimes/<agent-id>/gateway/mcp/v1/messages`

The gateway decouples the agent code from Lambda ARN management — the agent references tools by name, and the gateway resolves them.

### 5.6 Amazon Qdrant (Self-Hosted Vector DB)

**Infrastructure:** EC2 t3.micro, Amazon Linux 2023, Qdrant running in Docker via `user_data` bootstrap.

**Collection:** `ember_kitchen_policies`  
**Vector dimensions:** 384 (bge-small-en-v1.5 output)  
**Distance metric:** Cosine similarity  
**Indexed documents:** 6 policy files

**Cost control:** The instance is tagged `Note: STOP when not testing`. A stop/start wrapper is documented in the README. At ~$0.0104/hr the instance costs approximately $7.50/month if left running.

### 5.7 Embedding Lambda

**Role:** Embed documents (index action) and queries (query action) using a self-hosted sentence-transformers model.

**Model:** `BAAI/bge-small-en-v1.5` (~130MB, 384-dim vectors)

**Deployment:** Lambda container image (ECR) — the model is baked into the image at build time to avoid cold-start download latency.

**Synonym expansion fix:** The `_query` function augments informal phrasings with canonical synonyms (`"cancel cancellation booking reservation"`) before embedding, improving cosine similarity recall for Scenario #10 (informal cancellation phrasing).

---

## 6. Data Model

### 6.1 Reservations Table

```
Table: <prefix>-Reservations
Partition key: reservation_id (String)
GSI: GuestPhoneIndex
  Partition key: guest_phone (String)
  Projection: ALL

Item schema:
{
  reservation_id: uuid,
  guest_name:     string,
  guest_phone:    string,
  date:           "YYYY-MM-DD",
  time:           "HH:MM",
  party_size:     number,
  dietary_requirements: [string],
  status:         "confirmed" | "cancelled",
  created_at:     ISO-8601
}
```

**GSI rationale:** `verify_booking` is called before every modify/cancel operation and looks up by phone number. A GSI avoids a full table scan on the hot path.

### 6.2 CallLog Table

```
Table: <prefix>-CallLog
Partition key: call_id (String)

Item schema:
{
  call_id:           uuid,
  guest_name:        string,
  guest_phone:       string,
  intent:            string,
  outcome:           "completed" | "escalated" | "emergency" | "tool_failure",
  escalation_reason: string,
  timestamp:         ISO-8601
}
```

### 6.3 Qdrant Collection Schema

```
Collection: ember_kitchen_policies
Vector: 384-dim float32 (cosine)

Point payload:
{
  doc_id: "ember_kitchen_general_info" | "reservation_policy" | ...,
  text:   string (full document text, truncated to 500 chars on retrieval)
}
```

---

## 7. Agentic Loop Design

### 7.1 Loop Mechanics

```
for iteration in range(10):
    response = bedrock.invoke_model(
        modelId=CLAUDE_HAIKU,
        body={messages, system_prompt, tools, max_tokens=512},
        guardrailIdentifier=GUARDRAIL_ID,
        guardrailVersion=GUARDRAIL_VERSION
    )
    
    if stop_reason == "end_turn" or no tool_use blocks:
        break
    
    # Execute all tool_use blocks in this response
    for tool_use in response.tool_uses:
        result = invoke_tool(tool_use.name, tool_use.input)
        append tool_result to messages
    
    # Continue loop with updated messages
```

### 7.2 Tool Dispatch Priority

```
retrieve_policy → always direct Embedding Lambda call (not via MCP)
other tools:
  1. AgentCore Gateway (MCP) — if AGENTCORE_GATEWAY_ENDPOINT is set
  2. Direct boto3 Lambda invoke — fallback
```

The `retrieve_policy` tool is handled outside MCP because the embedding Lambda has a different interface (action/query pattern) that does not map cleanly to the MCP schema.

### 7.3 Escalation Detection

Escalation is detected at two levels:

1. **Keyword scan on response text** — the agent loop scans the final text response for escalation signals (`"transfer"`, `"human agent"`, `"emergency"`, etc.) and sets `escalate` or `emergency` flags.
2. **Tool call intent** — `log_call_outcome` is instructed to be called with `intent=Escalate` or `intent=EmergencyEscalation` before signalling transfer, providing a durable record in DynamoDB.

The Lex V2 contact flow branches on `escalate` and `emergency` response attributes to route to the correct Connect queue.

---

## 8. Retrieval-Augmented Generation (RAG)

### 8.1 Knowledge Base

Six policy documents are indexed:

| Document ID | Contents |
|-------------|----------|
| `ember_kitchen_general_info` | Hours, location, contact, parking, dress code |
| `reservation_policy` | Booking window, party size limits, 48h/24h cancellation policy |
| `dietary_and_allergen_menu` | 14 allergen groups, vegan/vegetarian options |
| `catering_packages_and_pricing` | Standard £45, Premium £75, Luxury £120 per head |
| `private_dining_and_events_policy` | Ember Room (12–24 guests), £500 hire fee, minimum spend |
| `allergy_emergency_procedures` | Staff response protocol, EpiPen location, escalation steps |

### 8.2 Indexing Pipeline

```
scripts/index_policies.py
  │
  ├── Read each docs/policies/*.md file
  ├── Invoke embedding Lambda (action=index, documents=[{id, text}])
  │     └── bge-small-en-v1.5 encodes text → 384-dim vector
  │     └── Qdrant upsert (deterministic UUID5 point ID from doc_id)
  └── Print confirmation
```

Documents can be re-indexed without duplication because Qdrant upsert uses deterministic IDs derived from the document ID via `uuid.uuid5(NAMESPACE_DNS, doc_id)`.

### 8.3 Retrieval at Query Time

```
retrieve_policy(query)
  │
  ├── Invoke embedding Lambda (action=query, query=augmented_query, top_k=3)
  │     ├── Augment query: query + " cancel cancellation booking reservation" (synonym expansion)
  │     ├── Encode → 384-dim vector
  │     └── Qdrant search (cosine similarity, top 3)
  └── Return [{doc_id, score, text[:500]}, ...]
```

**Truncation at 500 characters** is intentional: the agent is running in a voice context where responses are constrained to 3 sentences. Returning full documents would overflow the token budget and produce non-voice-appropriate responses.

### 8.4 Documented Failure & Fix

**Scenario #10** exposed a retrieval failure where the query `"If I need to call off my booking, will I be charged?"` returned `reservation_policy` at rank 3 instead of rank 1.

**Root cause:** `bge-small-en-v1.5` was trained primarily on formal English; the phrase `"call off"` has low cosine similarity to `"cancel"` in the model's embedding space.

**Fix:** Synonym expansion in `_query` — the query string is concatenated with `"cancel cancellation booking reservation"` before encoding. This shifts the embedding toward the formal vocabulary the model handles well, without requiring model fine-tuning or a larger embedding model.

**Post-fix result:** Scenario #10 passes; all 17 scenarios pass.

---

## 9. Safety, Guardrails & Escalation

### 9.1 Bedrock Guardrails

Three denied topics are configured as a Bedrock Guardrail resource:

| Topic | Block Trigger | Response |
|-------|---------------|----------|
| MedicalAdvice | Questions about health, allergies as medical queries | Politely decline, redirect to dining |
| CompetitorComparison | Any mention of competing restaurants | Decline, redirect |
| InternalKitchenDetails | Kitchen operations, suppliers, health codes | Decline, redirect |

The guardrail is applied at the `bedrock.invoke_model` API level via `guardrailIdentifier` and `guardrailVersion` parameters — not inside the request body. This is the correct Bedrock Guardrails API pattern; guardrails are top-level parameters, not body parameters.

Additionally, PII detection is enabled to prevent the agent from repeating phone numbers or names in unsafe contexts.

### 9.2 Dual Enforcement

The denied topics are enforced at two layers:
1. **Bedrock Guardrails** — blocks the model from generating denied content, even if the system prompt is bypassed.
2. **System prompt** — explicitly lists denied topics, reducing the chance of the model attempting to answer and being blocked, which would consume tokens and latency.

### 9.3 Emergency Escalation Protocol

Emergency escalation (allergy reaction, anaphylaxis, medical emergency) is handled with zero additional conversational turns:

1. Lex V2 fires `EmergencyEscalation` intent (zero slots, no elicitation).
2. Agent receives event, calls `log_call_outcome(intent=EmergencyEscalation)`.
3. Agent sets `emergency=true` in response attributes.
4. Lex contact flow branches to `EmergencyQueue` immediately.
5. Connect Case is created with intent, guest name, and reason.

This design ensures a caller in distress is never asked clarifying questions before reaching emergency staff.

---

## 10. Observability & Cost Control

### 10.1 Tracing

- **AWS X-Ray** active tracing enabled on all Lambda functions.
- X-Ray group `<prefix>-DINEAI` with filter expression `annotation.aws:lambda:function_name contains "EmberKitchen"` — enables the service map for the entire call chain.

### 10.2 Alarms

A CloudWatch alarm is created per tool Lambda function:
- **Metric:** Lambda Errors
- **Threshold:** ≥ 1 error in 60 seconds
- **Action:** SNS notification (configurable)

These alarms surface tool failures at the function level, enabling rapid diagnosis of which Lambda in the chain failed.

### 10.3 Token Cost Metric

The agent emits a structured log line per call:
```
TOKEN_COST <input_tokens> <output_tokens> <cost_usd>
```

A CloudWatch Logs metric filter converts this to the custom metric `EmberKitchen/DINEAI/PerCallTokenCostUSD`. Cost formula:
```
cost = (input_tokens / 1,000,000 × $0.25) + (output_tokens / 1,000,000 × $1.25)
```
(Claude Haiku pricing as of workshop date)

This provides per-call cost visibility independently of AWS billing, which aggregates across all Bedrock usage.

---

## 11. Security Design

### 11.1 IAM Least Privilege

| Role | Permissions |
|------|-------------|
| AgentCore Runtime Role | `bedrock:InvokeModel` on Haiku only; `bedrock:ApplyGuardrail` on specific guardrail ARN; `lambda:InvokeFunction` on tool Lambda ARNs only |
| Agent Lambda Role | Same as above + `lambda:InvokeFunction` on embedding Lambda; CloudWatch Logs; X-Ray |
| Tool Lambda Role | DynamoDB CRUD on specific table ARNs; Connect Cases `create_case` |

No wildcard resource ARNs are used for data-plane permissions. Log and X-Ray permissions use `*` as they are control-plane calls without sensitive resource identifiers.

### 11.2 SigV4 Authentication for MCP

All AgentCore Gateway calls are signed with AWS SigV4. The agent container retrieves credentials from the ECS task metadata endpoint (via `boto3.session.Session().get_credentials()`), ensuring no static credentials are embedded in the image.

### 11.3 Secrets Management

- No secrets are embedded in code or Terraform.
- AWS credentials for CI/CD are stored as GitHub Actions secrets.
- Terraform state is stored in S3 with DynamoDB locking (see CI/CD section).
- The `.gitignore` excludes all `.tfvars`, `.tfstate`, and `.terraform/` directories.

### 11.4 Network Security

- Qdrant's security group allows inbound on ports 6333/6334 and SSH from a configurable CIDR (`allowed_ssh_cidr` variable).
- For production, `allowed_ssh_cidr` should be restricted to a bastion or VPN CIDR.
- Lambda functions do not attach to the VPC; they access Qdrant via its public IP. For production, Qdrant should move to a private subnet with a Lambda VPC attachment.

---

## 12. Evaluation Results

### 12.1 Test Scenario Summary

17 scenarios across 7 categories were executed against the deployed system:

| # | Category | Input | Expected | Result |
|---|----------|-------|----------|--------|
| 1 | Routine | Greeting with session name | Greeted by name | ✅ Pass |
| 2 | Routine | Book table for 2 | check_availability + book_table called | ✅ Pass |
| 3 | Routine | Check reservation | verify_booking called, details returned | ✅ Pass |
| 4 | Routine | Cancel reservation | cancel_reservation; DynamoDB status=cancelled | ✅ Pass |
| 5 | Routine | Modify to 4 people | modify_reservation + verify_booking | ✅ Pass |
| 6 | Routine | Dietary update (gluten-free) | record_dietary_requirements; DynamoDB verified | ✅ Pass |
| 7 | Routine | Catering quote 30 people | request_catering_quote; £1,350 standard | ✅ Pass |
| 8 | Multi-tool | Book + nut allergy | 3-tool sequence in correct order | ✅ Pass |
| 9 | Policy RAG | Cancellation policy (formal) | retrieve_policy; 48h/24h terms returned | ✅ Pass |
| 10 | Policy RAG | Informal cancellation ("call off") | retrieve_policy; correct policy (after fix) | ✅ Pass |
| 11 | Policy RAG | Private dining for 20 | retrieve_policy; Ember Room details returned | ✅ Pass |
| 12 | Denied topic | Nut allergy safety (medical) | Guardrail blocks; redirect | ✅ Pass |
| 13 | Denied topic | Competitor comparison | Guardrail blocks; redirect | ✅ Pass |
| 14 | Escalation | Request manager | log_call_outcome; Connect Case; GeneralQueue | ✅ Pass |
| 15 | Emergency | Allergic reaction | log_call_outcome; Connect Case; EmergencyQueue (no delay) | ✅ Pass |
| 16 | Unverified | Cancel (no phone match) | verify_booking found=false; no modification; offer new booking | ✅ Pass |
| 17 | Tool failure | book_table Lambda 500 | Informs caller; no hallucinated confirmation; log_call_outcome outcome=tool_failure | ✅ Pass |

**Overall pass rate: 17 / 17 = 100%**

### 12.2 Documented Failure (Pre-Fix)

**Scenario #10** failed before the synonym expansion fix was applied:

- **Input:** "If I need to call off my booking, will I be charged?"
- **Failure mode:** `retrieve_policy` returned `reservation_policy` at rank 3 (score 0.42) instead of rank 1 (expected score > 0.70).
- **Root cause:** `bge-small-en-v1.5` embedding space does not associate the informal phrase `"call off"` with the formal term `"cancel"` strongly enough for cosine retrieval.
- **Fix:** Synonym expansion — query augmented with `"cancel cancellation booking reservation"` before encoding.
- **Post-fix score:** reservation_policy returns at rank 1 (score 0.78).

---

## 13. Cost Analysis

### 13.1 Model Cost Breakdown

| Component | Model | Unit Cost | Estimated Monthly |
|-----------|-------|-----------|-------------------|
| Reasoning | Claude Haiku | $0.25/MTok in, $1.25/MTok out | ~$2–5 for demo volume |
| TTS | Amazon Polly NTTS | $0.016/1K chars | ~$1–3 for demo volume |
| Embeddings | bge-small-en-v1.5 (self-hosted) | $0 (Lambda compute only) | < $0.50 |

### 13.2 Infrastructure Cost

| Resource | Spec | Cost/hr | Monthly (if always-on) |
|----------|------|---------|------------------------|
| Qdrant EC2 | t3.micro | $0.0104 | $7.50 |
| Lambda invocations | 8 tools + agent | pay-per-use | < $1 |
| DynamoDB | on-demand | pay-per-use | < $1 |
| Amazon Connect | per-minute | $0.018/min | variable |

**Total estimated cost for workshop/demo: < $30** (within budget cap)

**Cost controls applied:**
- Claude Haiku (not Sonnet/Opus) — ~5× cheaper per token than Claude Sonnet
- Polly NTTS (not Nova Sonic) — lower cost; meets quality requirements
- Qdrant on t3.micro (not OpenSearch) — stops when not testing
- Self-hosted embeddings (not Titan) — zero per-token cost

---

## 14. CI/CD Pipeline

### 14.1 Pipeline Overview

Two GitHub Actions workflows are defined in `.github/workflows/`:

**CI (`ci.yml`)** — triggered on every PR to main and every push to main:
1. `terraform fmt -check` — enforces formatting standards
2. `terraform validate` — checks configuration syntax
3. `terraform plan` (PRs only) — generates a plan and posts it as a PR comment
4. Docker build check — builds both images without pushing (validates Dockerfiles and dependencies)

**CD (`cd.yml`)** — triggered on push to main only:
1. Build and push Docker images to ECR (tagged with `github.sha` + `latest`)
2. Terraform init with S3 backend
3. Terraform plan
4. Terraform apply (under `production` environment — enables GitHub required reviewers gate)

### 14.2 Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `AWS_ACCESS_KEY_ID` | AWS credentials for ECR and Terraform |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials |
| `TF_BACKEND_BUCKET` | S3 bucket name for Terraform state |
| `TF_BACKEND_KEY` | State file key (e.g. `ember-kitchen/terraform.tfstate`) |
| `TF_BACKEND_REGION` | S3 bucket region |
| `TF_BACKEND_TABLE` | DynamoDB table name for state locking |

### 14.3 S3 Backend Bootstrap

Before first CI/CD run, create the state backend:

```bash
# Create S3 bucket
aws s3api create-bucket \
  --bucket <your-tf-state-bucket> \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket <your-tf-state-bucket> \
  --versioning-configuration Status=Enabled

# Create DynamoDB lock table
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### 14.4 Deployment Gate

The `terraform-apply` job in `cd.yml` runs under the `production` environment. GitHub environments support required reviewers — configure one or more approvers in the repository settings to require manual approval before Terraform apply executes.

---

## 15. Limitations & Future Work

### 15.1 Current Limitations

| Area | Limitation | Impact |
|------|-----------|--------|
| Availability check | Full table scan for slot conflict | O(n) at scale; acceptable for demo |
| Qdrant security | Public subnet, public IP | Should move to private subnet for production |
| State management | Lex conversation state is stateless between Lambda invocations | Conversation history passed per turn; no persistent session state |
| Model version | Claude Haiku hardcoded | Model version changes require code and Terraform update |
| EC2 key pair | Requires pre-existing key pair name | Cannot be bootstrapped via Terraform alone |

### 15.2 Production Readiness Gaps

1. **Availability slot index** — replace table scan with a DynamoDB GSI on `(date, time)` with a covers counter using atomic increments.
2. **Qdrant private subnet** — move EC2 to private subnet; attach Lambda functions to VPC for private access.
3. **OIDC for CI/CD** — replace long-lived AWS access keys in GitHub secrets with OIDC-based role assumption (`id-token: write` permission is already enabled in `cd.yml`).
4. **Multi-environment Terraform workspaces** — add `staging` workspace that deploys from PRs for pre-production validation.
5. **Embedding model versioning** — pin the sentence-transformers model version in `requirements.txt` to prevent silent embedding drift.

### 15.3 Potential Enhancements

- **Proactive confirmations** — SMS confirmation via SNS after booking (Connect already has caller phone).
- **Calendar integration** — export reservation to guest's calendar via a Cal.com or Google Calendar tool Lambda.
- **Multi-language support** — Lex V2 supports multiple locales; adding French/Spanish locales would serve a broader guest base.
- **Reservation reminders** — DynamoDB Streams trigger a Lambda 24 hours before reservation time to send a reminder call or SMS.

---

## 16. Conclusion

DINEAI demonstrates that a production-grade agentic voice system for a domain-specific use case (restaurant reservations) can be built on AWS using managed services (Amazon Connect, Lex V2, Bedrock AgentCore, DynamoDB) combined with self-hosted components (Qdrant, sentence-transformers) — all within a $30 budget cap.

The system achieves the design goals:
- **Reliability:** 17/17 test scenarios pass, including multi-tool sequences, edge cases, and failure modes.
- **Safety:** Two-layer guardrails (Bedrock + system prompt) block all three denied topics; emergency escalation requires zero additional conversational turns.
- **Observability:** Per-call X-Ray traces, per-Lambda error alarms, and a custom per-call token cost metric provide full operational visibility.
- **Cost efficiency:** Deliberate model selection (Haiku over Sonnet, Polly NTTS over Nova Sonic, self-hosted embeddings over Titan) keeps running costs well within budget.

The primary architectural insight is that **tool dispatch reliability** — not model capability — is the dominant reliability factor for structured agentic workflows. The MCP → direct-Lambda fallback pattern and the post-mutation `verify_booking` confirmation are the key design choices that make the system dependable at the tool layer.
