#!/usr/bin/env python3
"""
run_eval.py — Run the 15 DINEAI evaluation scenarios against the live agent Lambda.

Usage:
    python scripts/evaluation/run_eval.py \\
        --function-name rabindra-EmberKitchen-demo-agent \\
        --region us-east-1 \\
        [--scenario TC-01]          # run a single scenario
        [--output results.json]     # save full results

Pass criteria (per scenario, defined in test_scenarios.json):
    response_contains_any   — at least one substring found in the response (case-insensitive)
    response_contains_none  — none of the substrings appear in the response
    tool_called             — the named tool was called at least once (requires agent to log tools)
    tools_called_include    — all listed tools were called
    tool_called_before      — tools were called in the given order
    escalate_flag           — response JSON has escalate=true
    emergency_flag          — response JSON has emergency=true
    no_additional_questions — no "?" in the agent response after declaring emergency

The agent Lambda must accept the event schema used in agent.py handler().
"""
import argparse
import json
import pathlib
import re
import sys
from datetime import datetime

import boto3

SCENARIOS_FILE = pathlib.Path(__file__).parent / "test_scenarios.json"


def invoke_agent(client, function_name: str, session_attrs: dict, history: list, user_msg: str) -> dict:
    payload = {
        "sessionAttributes": session_attrs,
        "conversationHistory": history,
        "inputText": user_msg,
    }
    resp = client.invoke(
        FunctionName=function_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload).encode(),
    )
    result = json.loads(resp["Payload"].read())
    if "FunctionError" in resp:
        raise RuntimeError(f"Lambda error: {result}")
    return result


def check_pass(turn_result: dict, pass_if: dict, tools_called: list[str]) -> tuple[bool, list[str]]:
    """Evaluate pass_if rules. Returns (passed, list_of_failures)."""
    response_text = turn_result.get("outputText", "").lower()
    failures = []

    if "response_contains_any" in pass_if:
        needles = [n.lower() for n in pass_if["response_contains_any"]]
        if not any(n in response_text for n in needles):
            failures.append(f"response_contains_any: none of {pass_if['response_contains_any']} found")

    if "response_contains_none" in pass_if:
        needles = [n.lower() for n in pass_if["response_contains_none"]]
        found = [n for n in needles if n in response_text]
        if found:
            failures.append(f"response_contains_none: found forbidden text {found}")

    if "tool_called" in pass_if:
        if pass_if["tool_called"] not in tools_called:
            failures.append(f"tool_called: '{pass_if['tool_called']}' was not called (called: {tools_called})")

    if "tools_called_include" in pass_if:
        missing = [t for t in pass_if["tools_called_include"] if t not in tools_called]
        if missing:
            failures.append(f"tools_called_include: missing {missing} (called: {tools_called})")

    if "tool_called_before" in pass_if:
        ordered = pass_if["tool_called_before"]
        indices = []
        for t in ordered:
            try:
                indices.append(tools_called.index(t))
            except ValueError:
                indices.append(-1)
        if indices != sorted(indices) or -1 in indices:
            failures.append(f"tool_called_before: {ordered} not called in order (called: {tools_called})")

    if "escalate_flag" in pass_if:
        if turn_result.get("escalate") is not True:
            failures.append("escalate_flag: response escalate!=true")

    if "emergency_flag" in pass_if:
        if turn_result.get("emergency") is not True:
            failures.append("emergency_flag: response emergency!=true")

    if "no_additional_questions" in pass_if and pass_if["no_additional_questions"]:
        if "?" in turn_result.get("outputText", ""):
            failures.append("no_additional_questions: agent asked a question after declaring emergency")

    return len(failures) == 0, failures


def run_scenario(client, function_name: str, scenario: dict) -> dict:
    sc_id = scenario["id"]
    history = []
    session_attrs = scenario.get("session_attributes", {})
    all_tools_called: list[str] = []
    turn_results = []
    passed = True
    failures = []

    for turn in scenario["turns"]:
        try:
            result = invoke_agent(client, function_name, session_attrs, history, turn["user"])
        except Exception as exc:
            passed = False
            failures.append(f"Lambda invocation failed: {exc}")
            break

        # Extract tools called from conversation history if agent embeds them
        new_history = result.get("conversationHistory", [])
        for msg in new_history[len(history):]:
            if isinstance(msg.get("content"), list):
                for block in msg["content"]:
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        all_tools_called.append(block["name"])

        history = new_history
        session_attrs = result.get("sessionAttributes", session_attrs)

        turn_ok, turn_failures = check_pass(result, turn.get("pass_if", {}), all_tools_called)
        if not turn_ok:
            passed = False
            failures.extend(turn_failures)

        turn_results.append({
            "user": turn["user"],
            "response": result.get("outputText", ""),
            "tools_called": list(all_tools_called),
            "escalate": result.get("escalate"),
            "emergency": result.get("emergency"),
        })

    status = "PASS" if passed else "FAIL"
    colour = "\033[92m" if passed else "\033[91m"
    reset = "\033[0m"
    print(f"{colour}[{status}]{reset} {sc_id} — {scenario['description']}")
    if failures:
        for f in failures:
            print(f"       ✗ {f}")

    return {
        "id": sc_id,
        "category": scenario["category"],
        "description": scenario["description"],
        "status": status,
        "failures": failures,
        "turns": turn_results,
    }


def main():
    parser = argparse.ArgumentParser(description="Run DINEAI evaluation scenarios")
    parser.add_argument("--function-name", required=True)
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--scenario", help="Run only this scenario ID (e.g. TC-01)")
    parser.add_argument("--output", help="Save full results to this JSON file")
    args = parser.parse_args()

    scenarios = json.loads(SCENARIOS_FILE.read_text())
    if args.scenario:
        scenarios = [s for s in scenarios if s["id"] == args.scenario]
        if not scenarios:
            print(f"Scenario {args.scenario} not found.", file=sys.stderr)
            sys.exit(1)

    client = boto3.client("lambda", region_name=args.region)

    print(f"\nDINEAI Evaluation — {len(scenarios)} scenario(s)\n{'─' * 60}")
    results = [run_scenario(client, args.function_name, s) for s in scenarios]

    passed = sum(1 for r in results if r["status"] == "PASS")
    total = len(results)
    rate = passed / total * 100 if total else 0

    print(f"\n{'─' * 60}")
    print(f"Result: {passed}/{total} passed  ({rate:.0f}%)")

    by_category: dict[str, list] = {}
    for r in results:
        by_category.setdefault(r["category"], []).append(r["status"])
    print("\nBy category:")
    for cat, statuses in sorted(by_category.items()):
        p = statuses.count("PASS")
        print(f"  {cat:25s} {p}/{len(statuses)}")

    if args.output:
        out = {
            "run_at": datetime.utcnow().isoformat() + "Z",
            "function_name": args.function_name,
            "total": total,
            "passed": passed,
            "pass_rate_pct": round(rate, 1),
            "results": results,
        }
        pathlib.Path(args.output).write_text(json.dumps(out, indent=2))
        print(f"\nFull results saved to: {args.output}")

    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
