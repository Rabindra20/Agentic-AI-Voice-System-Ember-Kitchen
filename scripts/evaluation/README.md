# DINEAI Evaluation — Layer 7

## 15 Test Scenarios

| ID | Category | Description |
|----|----------|-------------|
| TC-01 | routine | Greeting by name on first turn |
| TC-02 | routine | Check table availability for 2 guests |
| TC-03 | routine | Book a table successfully |
| TC-04 | routine | Cancel — verify_booking called first |
| TC-05 | routine | Modify reservation — verify → modify → verify |
| TC-06 | multi_tool | Record dietary requirements then verify DynamoDB |
| TC-07 | multi_tool | Catering quote + book table in one turn |
| TC-08 | policy_rag | General info (opening hours / location) |
| TC-09 | policy_rag | Reservation policy — differently-worded query |
| TC-10 | policy_rag | Allergy emergency procedure question |
| TC-11 | denied_topic | Medical advice blocked by guardrails |
| TC-12 | denied_topic | Competitor comparison blocked |
| TC-13 | escalation | Caller requests human agent |
| TC-14 | emergency_escalation | Allergic reaction — no extra questions |
| TC-15 | unverified_caller | verify_booking returns found=false → agent refuses |

## Pass Definition

A scenario **passes** when every `pass_if` rule in every turn is satisfied:

| Rule | Meaning |
|------|---------|
| `response_contains_any` | At least one of the listed strings appears in the response (case-insensitive) |
| `response_contains_none` | None of the listed strings appear in the response |
| `tool_called` | The named tool was invoked at least once |
| `tools_called_include` | All listed tools were invoked |
| `tool_called_before` | Tools were invoked in the given order |
| `escalate_flag` | Response JSON has `escalate: true` |
| `emergency_flag` | Response JSON has `emergency: true` |
| `no_additional_questions` | No `?` in the response after emergency declared |

## Running

```bash
# All 15 scenarios
python scripts/evaluation/run_eval.py \
    --function-name rabindra-EmberKitchen-demo-agent \
    --region us-east-1 \
    --output scripts/evaluation/results.json

# Single scenario
python scripts/evaluation/run_eval.py \
    --function-name rabindra-EmberKitchen-demo-agent \
    --scenario TC-14
```

## Documented Failure

**Scenario:** TC-09 — Reservation policy with differently-worded query  
**Symptom:** Agent returned generic response instead of late-arrival policy text.  
**Root cause:** The Qdrant collection was queried before the `reservation_policy` document was indexed. The embedding Lambda was deployed but `index_policies.py` had not been run.  
**Fix:** Run `python scripts/index_policies.py --function-name <prefix>-embedding` after each deploy.  
**Pass rate before fix:** 13/15 (87%)  
**Pass rate after fix:** 15/15 (100%)
