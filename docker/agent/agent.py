"""
DINEAI Agent — runs inside AgentCore Runtime container.
Handles the agent loop: receives Connect events, calls Claude Haiku via Bedrock,
invokes tools through AgentCore Gateway (MCP), and returns responses.

Tool dispatch priority:
  1. AgentCore Gateway (MCP) — when AGENTCORE_GATEWAY_ENDPOINT is set (production)
  2. Direct Lambda invoke (boto3) — fallback for local testing / Gateway unavailable
"""
import json
import logging
import os
import uuid
from typing import Any

import boto3
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)
lambda_client = boto3.client("lambda", region_name=AWS_REGION)

MODEL_ID = os.environ.get("CLAUDE_MODEL_ID", "anthropic.claude-haiku-20240307-v1:0")
GUARDRAIL_ID = os.environ.get("GUARDRAIL_ID", "")
GUARDRAIL_VERSION = os.environ.get("GUARDRAIL_VERSION", "1")
EMBEDDING_LAMBDA = os.environ.get("EMBEDDING_LAMBDA_NAME", "")

# AgentCore Gateway MCP endpoint — injected by the runtime when deployed.
# When set, all tool calls go through MCP (correct path per spec).
# When empty, falls back to direct Lambda invocation (local/test path).
GATEWAY_ENDPOINT = os.environ.get("AGENTCORE_GATEWAY_ENDPOINT", "")

TOOL_LAMBDAS = {
    "verify_booking":             os.environ.get("LAMBDA_verify_booking", ""),
    "check_table_availability":   os.environ.get("LAMBDA_check_table_availability", ""),
    "book_table":                 os.environ.get("LAMBDA_book_table", ""),
    "modify_reservation":         os.environ.get("LAMBDA_modify_reservation", ""),
    "cancel_reservation":         os.environ.get("LAMBDA_cancel_reservation", ""),
    "record_dietary_requirements":os.environ.get("LAMBDA_record_dietary_requirements", ""),
    "request_catering_quote":     os.environ.get("LAMBDA_request_catering_quote", ""),
    "log_call_outcome":           os.environ.get("LAMBDA_log_call_outcome", ""),
}

TOOLS = [
    {
        "name": "verify_booking",
        "description": "Verify if a guest has an existing reservation by phone number.",
        "input_schema": {
            "type": "object",
            "properties": {"guest_phone": {"type": "string", "description": "Guest phone number"}},
            "required": ["guest_phone"],
        },
    },
    {
        "name": "check_table_availability",
        "description": "Check if a table is available for a given date, time, and party size.",
        "input_schema": {
            "type": "object",
            "properties": {
                "date":       {"type": "string", "description": "Date in YYYY-MM-DD format"},
                "time":       {"type": "string", "description": "Time in HH:MM format"},
                "party_size": {"type": "integer", "description": "Number of guests"},
            },
            "required": ["date", "time"],
        },
    },
    {
        "name": "book_table",
        "description": "Create a new table reservation.",
        "input_schema": {
            "type": "object",
            "properties": {
                "guest_name":  {"type": "string"},
                "guest_phone": {"type": "string"},
                "date":        {"type": "string"},
                "time":        {"type": "string"},
                "party_size":  {"type": "integer"},
                "dietary_requirements": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["guest_name", "guest_phone", "date", "time", "party_size"],
        },
    },
    {
        "name": "modify_reservation",
        "description": "Modify an existing reservation.",
        "input_schema": {
            "type": "object",
            "properties": {
                "reservation_id": {"type": "string"},
                "date":           {"type": "string"},
                "time":           {"type": "string"},
                "party_size":     {"type": "integer"},
            },
            "required": ["reservation_id"],
        },
    },
    {
        "name": "cancel_reservation",
        "description": "Cancel an existing reservation.",
        "input_schema": {
            "type": "object",
            "properties": {"reservation_id": {"type": "string"}},
            "required": ["reservation_id"],
        },
    },
    {
        "name": "record_dietary_requirements",
        "description": "Record dietary requirements or allergies for a reservation.",
        "input_schema": {
            "type": "object",
            "properties": {
                "reservation_id":       {"type": "string"},
                "dietary_requirements": {"type": "array", "items": {"type": "string"}},
            },
            "required": ["reservation_id", "dietary_requirements"],
        },
    },
    {
        "name": "request_catering_quote",
        "description": "Get a catering quote for an event.",
        "input_schema": {
            "type": "object",
            "properties": {
                "package":     {"type": "string", "enum": ["standard", "premium", "luxury"]},
                "guests":      {"type": "integer"},
            },
            "required": ["guests"],
        },
    },
    {
        "name": "log_call_outcome",
        "description": "Log the outcome of the call. Call this at the end of every interaction.",
        "input_schema": {
            "type": "object",
            "properties": {
                "call_id":           {"type": "string"},
                "guest_name":        {"type": "string"},
                "guest_phone":       {"type": "string"},
                "intent":            {"type": "string"},
                "outcome":           {"type": "string"},
                "escalation_reason": {"type": "string"},
            },
            "required": ["intent", "outcome"],
        },
    },
    {
        "name": "retrieve_policy",
        "description": "Retrieve Ember Kitchen policy information from the knowledge base. Use for questions about reservations, dietary info, catering, private dining, allergy procedures, or general info.",
        "input_schema": {
            "type": "object",
            "properties": {"query": {"type": "string", "description": "The question to look up"}},
            "required": ["query"],
        },
    },
]


def _mcp_call(tool_name: str, tool_input: dict) -> str:
    """
    Call a tool via AgentCore Gateway using the MCP JSON-RPC protocol.
    Requests are SigV4-signed with the container's task role credentials.
    MCP spec: https://modelcontextprotocol.io/specification
    """
    session = boto3.session.Session()
    credentials = session.get_credentials().get_frozen_credentials()

    url = f"{GATEWAY_ENDPOINT}/mcp/v1/messages"
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": str(uuid.uuid4()),
        "method": "tools/call",
        "params": {
            "name": tool_name,
            "arguments": tool_input,
        },
    })

    # Sign with SigV4 — service name for AgentCore Gateway is "bedrock"
    aws_req = AWSRequest(
        method="POST",
        url=url,
        data=body.encode(),
        headers={"Content-Type": "application/json"},
    )
    SigV4Auth(credentials, "bedrock", AWS_REGION).add_auth(aws_req)

    resp = requests.post(url, data=body, headers=dict(aws_req.headers), timeout=30)
    resp.raise_for_status()
    result = resp.json()

    if "error" in result:
        return json.dumps({"error": result["error"]})

    # MCP tool result: {"result": {"content": [{"type": "text", "text": "..."}]}}
    content_blocks = result.get("result", {}).get("content", [])
    text = " ".join(b.get("text", "") for b in content_blocks if b.get("type") == "text")
    return text or json.dumps(result.get("result", {}))


def _invoke_lambda_direct(tool_name: str, tool_input: dict) -> str:
    """Direct boto3 Lambda invocation — used when Gateway endpoint is not set."""
    fn_name = TOOL_LAMBDAS.get(tool_name)
    if not fn_name:
        return json.dumps({"error": f"Unknown tool: {tool_name}"})
    resp = lambda_client.invoke(
        FunctionName=fn_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(tool_input),
    )
    return json.dumps(json.loads(resp["Payload"].read()))


def _invoke_tool(tool_name: str, tool_input: dict) -> str:
    if tool_name == "retrieve_policy":
        return _retrieve_policy(tool_input["query"])

    try:
        if GATEWAY_ENDPOINT:
            # Production path: MCP via AgentCore Gateway
            return _mcp_call(tool_name, tool_input)
        else:
            # Local/test path: direct Lambda invocation
            return _invoke_lambda_direct(tool_name, tool_input)
    except Exception as exc:
        logger.error("Tool %s failed: %s", tool_name, exc)
        if GATEWAY_ENDPOINT:
            # Gateway failed — try direct Lambda as emergency fallback
            logger.warning("Retrying %s via direct Lambda after MCP failure", tool_name)
            try:
                return _invoke_lambda_direct(tool_name, tool_input)
            except Exception as exc2:
                logger.error("Direct Lambda fallback also failed: %s", exc2)
        return json.dumps({"error": str(exc)})


def _retrieve_policy(query: str) -> str:
    if not EMBEDDING_LAMBDA:
        return json.dumps({"error": "Embedding Lambda not configured"})
    try:
        resp = lambda_client.invoke(
            FunctionName=EMBEDDING_LAMBDA,
            InvocationType="RequestResponse",
            Payload=json.dumps({"action": "query", "query": query, "top_k": 3}),
        )
        return resp["Payload"].read().decode()
    except Exception as exc:
        logger.error("RAG retrieval failed: %s", exc)
        return json.dumps({"error": str(exc)})


def run_agent(session_attributes: dict, conversation_history: list, user_message: str) -> dict:
    """
    Single agent turn. Returns {"response": str, "history": list, "escalate": bool, "emergency": bool}.
    Logs token cost to CloudWatch via structured log line.
    """
    guest_name = session_attributes.get("guest_name", "")
    messages = conversation_history + [{"role": "user", "content": user_message}]

    system_prompt = f"""You are DINEAI, the AI voice assistant for Ember Kitchen, a premium London restaurant.
Operating hours: Tuesday to Sunday, 10:00 AM to 10:00 PM. Closed Monday.

GREETING: Guest name is '{guest_name or "unknown — ask for it"}'. Greet by name on the first turn.

TOOLS: Use the provided tools for all reservation and dining operations.
- Before modifying or cancelling any reservation, call verify_booking with the caller's phone number.
  If verify_booking returns found=false, do not modify or cancel — offer to create a new booking instead.
- After any reservation or dietary update (book_table, modify_reservation, record_dietary_requirements),
  call verify_booking again to confirm the DynamoDB record was updated correctly.
- Always call log_call_outcome at the end of every call.

VOICE: Keep responses under 3 sentences. This is a phone call.

ESCALATION:
- If the caller requests a human agent: call log_call_outcome (intent=Escalate), then indicate transfer.
- If the caller mentions an allergic reaction, anaphylaxis, or medical emergency: immediately call
  log_call_outcome (intent=EmergencyEscalation) and indicate emergency transfer. No additional questions.

DENIED TOPICS — never discuss:
1. Medical advice or health recommendations
2. Comparisons with competitor restaurants
3. Internal kitchen operations, health codes, or supplier details
Politely decline and redirect to dining assistance.

POLICY QUESTIONS: Use retrieve_policy for questions about general info, reservation policy,
dietary and allergen menu, catering packages, private dining, or allergy emergency procedures."""

    total_input_tokens = 0
    total_output_tokens = 0
    escalate = False
    emergency = False
    final_response = ""

    # Agentic loop
    for _ in range(10):  # max 10 tool calls per turn
        invoke_kwargs: dict[str, Any] = {
            "modelId": MODEL_ID,
            "body": json.dumps({
                "anthropic_version": "bedrock-2023-05-31",
                "system": system_prompt,
                "messages": messages,
                "tools": TOOLS,
                "max_tokens": 512,
            }),
        }
        # Guardrails are top-level invoke_model params, not inside the body.
        if GUARDRAIL_ID:
            invoke_kwargs["guardrailIdentifier"] = GUARDRAIL_ID
            invoke_kwargs["guardrailVersion"] = GUARDRAIL_VERSION
            invoke_kwargs["trace"] = "ENABLED"

        resp = bedrock.invoke_model(**invoke_kwargs)
        body = json.loads(resp["body"].read())

        usage = body.get("usage", {})
        total_input_tokens += usage.get("input_tokens", 0)
        total_output_tokens += usage.get("output_tokens", 0)

        stop_reason = body.get("stop_reason")
        content = body.get("content", [])

        # Collect text and tool_use blocks
        text_parts = [b["text"] for b in content if b.get("type") == "text"]
        tool_uses = [b for b in content if b.get("type") == "tool_use"]

        if text_parts:
            final_response = " ".join(text_parts)

        # Check escalation keywords in response
        lower = final_response.lower()
        if "emergency" in lower or "allergic reaction" in lower or "anaphylaxis" in lower:
            emergency = True
        if "transfer" in lower or "human agent" in lower or "speak to someone" in lower:
            escalate = True

        if stop_reason == "end_turn" or not tool_uses:
            break

        # Execute tools and continue loop
        messages.append({"role": "assistant", "content": content})
        tool_results = []
        for tu in tool_uses:
            result = _invoke_tool(tu["name"], tu.get("input", {}))
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tu["id"],
                "content": result,
            })
        messages.append({"role": "user", "content": tool_results})

    # Append final assistant message
    messages.append({"role": "assistant", "content": final_response})

    # Log token cost (picked up by CloudWatch metric filter)
    cost_usd = (total_input_tokens / 1_000_000 * 0.25) + (total_output_tokens / 1_000_000 * 1.25)
    logger.info(
        "TOKEN_COST %d %d %.6f",
        total_input_tokens, total_output_tokens, cost_usd,
    )

    return {
        "response": final_response,
        "history": messages,
        "escalate": escalate,
        "emergency": emergency,
    }


def handler(event, _context):
    """Lambda/AgentCore entry point."""
    session_attributes = event.get("sessionAttributes", {})
    history = event.get("conversationHistory", [])
    user_message = event.get("inputText", "")

    result = run_agent(session_attributes, history, user_message)
    return {
        "statusCode": 200,
        "sessionAttributes": session_attributes,
        "conversationHistory": result["history"],
        "outputText": result["response"],
        "escalate": result["escalate"],
        "emergency": result["emergency"],
    }


if __name__ == "__main__":
    # Local smoke test
    test_event = {
        "sessionAttributes": {"guest_name": "Alice"},
        "conversationHistory": [],
        "inputText": "Hi, I'd like to book a table for 2 on Friday at 7pm.",
    }
    print(json.dumps(handler(test_event, None), indent=2))
