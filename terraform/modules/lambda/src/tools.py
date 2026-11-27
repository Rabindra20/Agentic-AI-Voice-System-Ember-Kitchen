"""
Ember Kitchen — Lambda tool handlers.
Each function is the handler for its corresponding Lambda function.
All functions receive the standard Lambda event/context.
"""
import json
import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
RESERVATIONS_TABLE = os.environ["RESERVATIONS_TABLE"]
CALL_LOG_TABLE = os.environ["CALL_LOG_TABLE"]
CONNECT_INSTANCE_ID = os.environ.get("CONNECT_INSTANCE_ID", "")
CONNECT_DOMAIN_ID = os.environ.get("CONNECT_DOMAIN_ID", "")

connect_cases = boto3.client("connectcases") if CONNECT_DOMAIN_ID else None


def _res_table():
    return dynamodb.Table(RESERVATIONS_TABLE)


def _log_table():
    return dynamodb.Table(CALL_LOG_TABLE)


def _ok(data: dict):
    return {"statusCode": 200, "body": json.dumps(data)}


def _err(msg: str, code: int = 400):
    return {"statusCode": code, "body": json.dumps({"error": msg})}


# ── verify_booking ─────────────────────────────────────────────────────────────
def verify_booking(event, _context):
    phone = event.get("guest_phone")
    if not phone:
        return _err("guest_phone required")
    result = _res_table().query(
        IndexName="GuestPhoneIndex",
        KeyConditionExpression=Key("guest_phone").eq(phone),
    )
    items = result.get("Items", [])
    return _ok({"found": bool(items), "reservations": items})


# ── check_table_availability ───────────────────────────────────────────────────
def check_table_availability(event, _context):
    date = event.get("date")
    time = event.get("time")
    party_size = event.get("party_size", 2)
    if not date or not time:
        return _err("date and time required")
    # Simplified: scan for conflicts (production would use a proper slot index)
    result = _res_table().scan(
        FilterExpression="#d = :d AND #t = :t",
        ExpressionAttributeNames={"#d": "date", "#t": "time"},
        ExpressionAttributeValues={":d": date, ":t": time},
    )
    booked_covers = sum(int(r.get("party_size", 0)) for r in result.get("Items", []))
    available = (50 - booked_covers) >= int(party_size)
    return _ok({"available": available, "remaining_covers": 50 - booked_covers})


# ── book_table ─────────────────────────────────────────────────────────────────
def book_table(event, _context):
    required = ["guest_name", "guest_phone", "date", "time", "party_size"]
    for field in required:
        if not event.get(field):
            return _err(f"{field} required")
    reservation_id = str(uuid.uuid4())
    item = {
        "reservation_id": reservation_id,
        "guest_name": event["guest_name"],
        "guest_phone": event["guest_phone"],
        "date": event["date"],
        "time": event["time"],
        "party_size": int(event["party_size"]),
        "dietary_requirements": event.get("dietary_requirements", []),
        "status": "confirmed",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    _res_table().put_item(Item=item)
    return _ok({"reservation_id": reservation_id, "status": "confirmed"})


# ── modify_reservation ─────────────────────────────────────────────────────────
def modify_reservation(event, _context):
    reservation_id = event.get("reservation_id")
    if not reservation_id:
        return _err("reservation_id required")
    updates = {k: v for k, v in event.items() if k not in ("reservation_id",) and v is not None}
    if not updates:
        return _err("no fields to update")
    expr = "SET " + ", ".join(f"#{k} = :{k}" for k in updates)
    names = {f"#{k}": k for k in updates}
    values = {f":{k}": v for k, v in updates.items()}
    _res_table().update_item(
        Key={"reservation_id": reservation_id},
        UpdateExpression=expr,
        ExpressionAttributeNames=names,
        ExpressionAttributeValues=values,
    )
    return _ok({"reservation_id": reservation_id, "updated": list(updates.keys())})


# ── cancel_reservation ─────────────────────────────────────────────────────────
def cancel_reservation(event, _context):
    reservation_id = event.get("reservation_id")
    if not reservation_id:
        return _err("reservation_id required")
    _res_table().update_item(
        Key={"reservation_id": reservation_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "cancelled"},
    )
    return _ok({"reservation_id": reservation_id, "status": "cancelled"})


# ── record_dietary_requirements ────────────────────────────────────────────────
def record_dietary_requirements(event, _context):
    reservation_id = event.get("reservation_id")
    requirements = event.get("dietary_requirements", [])
    if not reservation_id:
        return _err("reservation_id required")
    _res_table().update_item(
        Key={"reservation_id": reservation_id},
        UpdateExpression="SET dietary_requirements = :r",
        ExpressionAttributeValues={":r": requirements},
    )
    return _ok({"reservation_id": reservation_id, "dietary_requirements": requirements})


# ── request_catering_quote ─────────────────────────────────────────────────────
def request_catering_quote(event, _context):
    package = event.get("package", "standard")
    guests = int(event.get("guests", 10))
    pricing = {"standard": 45, "premium": 75, "luxury": 120}
    per_head = pricing.get(package, 45)
    return _ok({
        "package": package,
        "guests": guests,
        "per_head_gbp": per_head,
        "total_estimate_gbp": per_head * guests,
        "note": "Final quote subject to menu confirmation.",
    })


# ── log_call_outcome ───────────────────────────────────────────────────────────
def log_call_outcome(event, _context):
    call_id = event.get("call_id", str(uuid.uuid4()))
    intent = event.get("intent", "unknown")
    escalation_reason = event.get("escalation_reason", "")
    item = {
        "call_id": call_id,
        "guest_name": event.get("guest_name", "unknown"),
        "guest_phone": event.get("guest_phone", "unknown"),
        "intent": intent,
        "outcome": event.get("outcome", "completed"),
        "escalation_reason": escalation_reason,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    _log_table().put_item(Item=item)

    # Auto-create a Connect Case for every escalation.
    case_id = None
    if connect_cases and CONNECT_DOMAIN_ID and escalation_reason:
        try:
            case_resp = connect_cases.create_case(
                domainId=CONNECT_DOMAIN_ID,
                templateId="Case",
                fields=[
                    {"id": "title",            "value": {"stringValue": f"Escalation: {intent}"}},
                    {"id": "status",           "value": {"stringValue": "Open"}},
                    {"id": "summary",          "value": {"stringValue": (
                        f"Guest: {item['guest_name']} ({item['guest_phone']})\n"
                        f"Intent: {intent}\n"
                        f"Escalation reason: {escalation_reason}"
                    )}},
                ],
            )
            case_id = case_resp.get("caseId")
        except Exception as exc:
            # Log but don't fail the call — cases are best-effort.
            print(f"Connect Cases creation failed: {exc}")

    return _ok({"call_id": call_id, "logged": True, "case_id": case_id})
