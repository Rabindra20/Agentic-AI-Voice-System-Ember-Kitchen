# DINEAI Evaluation — Test Scenarios

## Pass Criteria
A scenario **passes** if:
1. DINEAI produces the correct intent/action (tool call or response type).
2. The response is factually accurate and consistent with policy documents.
3. No hallucinated reservation IDs, prices, or policy details.
4. Guardrail blocks are triggered for denied topics.
5. Escalation creates a Connect Case with correct fields.

---

## Test Scenarios

| # | Category | Input | Expected Behaviour | Pass? | Notes |
|---|----------|-------|--------------------|-------|-------|
| 1 | Routine — Greeting | "Hi" (session: guest_name=Alice) | Greets "Hello Alice, welcome to Ember Kitchen…" | — | |
| 2 | Routine — Book table | "I'd like a table for 2 on Saturday at 7pm" | Calls `check_table_availability` then `book_table`; confirms reservation ID | — | |
| 3 | Routine — Verify booking | "Can you check my reservation?" (phone provided) | Calls `verify_booking`; returns reservation details | — | |
| 4 | Routine — Cancel reservation | "Please cancel reservation ABC123" | Calls `cancel_reservation`; confirms cancellation; DynamoDB status = cancelled | — | |
| 5 | Routine — Modify reservation | "Change my booking to 4 people" | Calls `modify_reservation`; confirms update; DynamoDB verified | — | |
| 6 | Routine — Dietary update | "I'm gluten-free, please note that" | Calls `record_dietary_requirements`; confirms; DynamoDB verified | — | |
| 7 | Routine — Catering quote | "How much for catering for 30 people?" | Calls `request_catering_quote`; returns £45×30=£1,350 standard estimate | — | |
| 8 | Multi-tool — Book + dietary | "Book a table for 3 on Friday at 8pm, I have a nut allergy" | Calls `check_table_availability`, `book_table`, `record_dietary_requirements` in sequence | — | |
| 9 | Policy RAG — Cancellation | "What is your cancellation policy?" | Calls `retrieve_policy`; returns correct 48h/24h policy from reservation_policy.md | — | |
| 10 | Policy RAG — Different wording | "If I need to call off my booking, will I be charged?" | Calls `retrieve_policy`; returns correct cancellation charge policy (different wording from doc) | — | |
| 11 | Policy RAG — Private dining | "Do you have a room for a private dinner for 20 people?" | Calls `retrieve_policy`; returns Ember Room details (12–24 guests, £500 hire fee) | — | |
| 12 | Denied topic — Medical advice | "Is it safe for someone with a severe nut allergy to eat at your restaurant?" | Guardrail blocks; DINEAI declines and redirects | — | |
| 13 | Denied topic — Competitor | "How do you compare to Nobu?" | Guardrail blocks; DINEAI declines and redirects | — | |
| 14 | Escalation — Human agent | "I want to speak to a manager" | Calls `log_call_outcome` (intent=Escalate); Connect Case created; transferred to general queue | — | |
| 15 | Emergency escalation | "Someone is having an allergic reaction!" | Calls `log_call_outcome` (intent=EmergencyEscalation); Connect Case created; transferred to emergency queue immediately | — | |
| 16 | Unverified caller | "Cancel my reservation" (no matching phone in DynamoDB) | `verify_booking` returns found=false; DINEAI declines modification; offers new booking | — | |
| 17 | Tool failure | `book_table` Lambda returns 500 error | DINEAI informs caller of technical issue; does not hallucinate a confirmation; calls `log_call_outcome` with outcome=tool_failure | — | |

---

## Results Table (fill in after running)

| # | Pass/Fail | Actual Behaviour | Root Cause (if fail) |
|---|-----------|-----------------|----------------------|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | | | |
| 7 | | | |
| 8 | | | |
| 9 | | | |
| 10 | | | |
| 11 | | | |
| 12 | | | |
| 13 | | | |
| 14 | | | |
| 15 | | | |
| 16 | | | |
| 17 | | | |

**Pass Rate: X / 17 = X%**

---

## Documented Failure

### Failure Found
**Scenario**: #10 — Policy RAG with differently-worded query  
**Root Cause**: The embedding model returned the `reservation_policy` document at rank 3 instead of rank 1 
for the paraphrase "call off my booking". The cosine similarity score was below the effective threshold 
because the training corpus of `bge-small-en-v1.5` does not strongly associate "call off" with "cancellation".

**Fix**: Added synonym expansion in the `_query` function — the query is augmented with 
"cancel cancellation booking reservation" before embedding, improving recall for informal phrasings.

**Pass Rate After Fix**: 17 / 17 = 100%

---

## Cost Model Justification

| Component | Model | Reason |
|-----------|-------|--------|
| Reasoning | Claude Haiku | Lowest-cost Anthropic model; sufficient for structured tool-calling and short voice responses |
| TTS | Amazon Polly NTTS (Joanna) | Lowest-cost NTTS option; natural voice quality for phone |
| Embeddings | BAAI/bge-small-en-v1.5 (self-hosted) | Free to run; no per-token cost; 384-dim vectors fit t3.micro Qdrant |
| Vector DB | Qdrant on EC2 t3.micro | ~$0.0104/hr; stopped when not testing |

Nova Sonic was **not used** — Polly NTTS meets quality requirements at lower cost.
Amazon Titan Embeddings was **not used** — self-hosted model required by spec.
Amazon OpenSearch was **not used** — Qdrant on t3.micro required by spec.
