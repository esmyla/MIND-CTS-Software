"""SAM — clinical data assistant for the doctor portal.

Tools and analysis by Paul. Auth reworked to use the doctor's own access token
instead of the service-role key, so RLS applies.
"""

import json
import os
import statistics
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from dotenv import load_dotenv
from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, SystemMessage, ToolMessage
from langchain_core.rate_limiters import InMemoryRateLimiter
from langchain_core.tools import tool
from langchain_openai import ChatOpenAI
from supabase import Client, create_client

load_dotenv()

# Older names kept so an existing local .env still works.
SUPABASE_URL = os.getenv("SUPABASE_URL") or os.getenv("SUPABASE_PROJECT_ID")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY") or os.getenv("SUPABASE_PUBLIC_KEY")

# `table` comes from the model, so anything unlisted must fail closed.
# patient_notes is left out on purpose: private clinical reasoning, and sending
# it to an external endpoint is a call nobody has made.
READABLE_TABLES = frozenset(
    {"baseline", "grip", "pinch", "flexion", "pt_sessions", "profiles", "doctor_patients"}
)
PATIENT_SCOPED_TABLES = frozenset({"baseline", "grip", "pinch", "flexion", "pt_sessions"})


@dataclass
class DoctorSession:
    access_token: str
    doctor_id: str
    doctor_name: str
    client: Client = field(repr=False)


def open_session(access_token: str) -> DoctorSession:
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        raise ValueError("Missing SUPABASE_URL or SUPABASE_ANON_KEY")

    client = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)

    user = getattr(client.auth.get_user(access_token), "user", None)
    if user is None:
        raise PermissionError("Invalid or expired access token.")

    # Attach the token so Postgres sees auth.uid() as this doctor.
    client.postgrest.auth(access_token)

    profile = (
        client.table("profiles").select("full_name, role").eq("user_id", user.id).limit(1).execute()
    )
    row = profile.data[0] if profile.data else {}
    if row.get("role") != "doctor":
        raise PermissionError("This account is not a doctor; SAM is for clinician use.")

    return DoctorSession(
        access_token=access_token,
        doctor_id=user.id,
        doctor_name=row.get("full_name") or user.email or "Unknown",
        client=client,
    )


def _normalize_end_date(end_date: Optional[str]) -> Optional[str]:
    if not end_date:
        return None
    clean = end_date.strip()
    if len(clean) == 10 and "T" not in clean and " " not in clean:
        return f"{clean}T23:59:59.999999+00:00"
    return clean


def _calc_stats(values: List[float], baseline_val: Optional[float] = None) -> Dict[str, Any]:
    clean = [float(v) for v in values if v is not None]
    if not clean:
        return {"count": 0, "mean": None, "min": None, "max": None, "pct_change_from_baseline": None}
    avg = round(statistics.mean(clean), 2)
    pct_change = None
    if baseline_val is not None and baseline_val != 0:
        pct_change = round(((avg - float(baseline_val)) / float(baseline_val)) * 100, 2)
    return {
        "count": len(clean),
        "mean": avg,
        "min": round(min(clean), 2),
        "max": round(max(clean), 2),
        "baseline": baseline_val,
        "pct_change_from_baseline": pct_change,
    }


# Built per session so the doctor's identity travels with the tool rather than
# sitting in a global that concurrent requests would overwrite.
def build_tools(session: DoctorSession) -> List[Any]:
    client = session.client

    def _verify_patient_access(patient_id: str) -> bool:
        resp = (
            client.table("doctor_patients")
            .select("id")
            .eq("doctor_id", session.doctor_id)
            .eq("patient_id", patient_id)
            .execute()
        )
        return len(resp.data) > 0

    @tool
    def find_users_and_rosters(name_or_email: Optional[str] = None) -> str:
        """
        Search for your assigned patients by partial name or email.
        If left blank, returns a list of ALL your assigned patients.
        """
        try:
            rel_resp = (
                client.table("doctor_patients")
                .select("patient_id")
                .eq("doctor_id", session.doctor_id)
                .execute()
            )
            patient_ids = [row["patient_id"] for row in rel_resp.data]
            if not patient_ids:
                return json.dumps({"assigned_patients": []})

            query = client.table("profiles").select("*").in_("user_id", patient_ids)
            if name_or_email:
                clean_term = name_or_email.strip()
                query = query.or_(f"full_name.ilike.%{clean_term}%,email.ilike.%{clean_term}%")

            return json.dumps(query.execute().data, indent=2)
        except Exception as e:
            return f"Error finding users: {str(e)}"

    @tool
    def get_patient_exercise_summary(
        user_id: str,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
    ) -> str:
        """
        Calculate averages, min/max, and percent change from baseline for a patient (user_id).
        """
        if not _verify_patient_access(user_id):
            return "Access Denied: You are not authorized to view this patient's data, or the patient does not exist."

        try:
            norm_end = _normalize_end_date(end_date)
            base_resp = (
                client.table("baseline").select("*").eq("user_id", user_id)
                .order("created_at", desc=True).limit(1).execute()
            )
            base = base_resp.data[0] if base_resp.data else {}

            def fetch_table(table_name: str):
                q = client.table(table_name).select("*").eq("user_id", user_id)
                if start_date:
                    q = q.gte("created_at", start_date)
                if norm_end:
                    q = q.lte("created_at", norm_end)
                return q.order("created_at", desc=False).execute().data

            grip_rows = fetch_table("grip")
            pinch_rows = fetch_table("pinch")
            flex_rows = fetch_table("flexion")

            summary = {
                "user_id": user_id,
                "date_filter": {"start_date": start_date, "end_date": norm_end},
                "baseline_recorded_at": base.get("created_at"),
                "grip_metrics": {
                    "total_rows": len(grip_rows),
                    "distinct_sessions": len({r.get("session_id") for r in grip_rows if r.get("session_id") is not None}),
                    "fsr_palm": _calc_stats([r.get("fsr_palm") for r in grip_rows], base.get("base_grip")),
                    "r_fsr_palm": _calc_stats([r.get("r_fsr_palm") for r in grip_rows]),
                    "bpm_avg": _calc_stats([r.get("bpm_avg") for r in grip_rows]),
                },
                "pinch_metrics": {
                    "total_rows": len(pinch_rows),
                    "distinct_sessions": len({r.get("session_id") for r in pinch_rows if r.get("session_id") is not None}),
                    "it_index_thumb": _calc_stats([r.get("it") for r in pinch_rows], base.get("base_it")),
                    "mt_middle_thumb": _calc_stats([r.get("mt") for r in pinch_rows], base.get("base_mt")),
                    "r_it": _calc_stats([r.get("r_it") for r in pinch_rows]),
                    "r_mt": _calc_stats([r.get("r_mt") for r in pinch_rows]),
                },
                "flexion_metrics": {
                    "total_rows": len(flex_rows),
                    "distinct_sessions": len({r.get("session_id") for r in flex_rows if r.get("session_id") is not None}),
                    "level_ups_achieved": sum(1 for r in flex_rows if r.get("level_up") is True),
                    "degree_forward": _calc_stats([r.get("degree_forward") for r in flex_rows], base.get("base_flex_deg")),
                    "degree_backwards": _calc_stats([r.get("degree_backwards") for r in flex_rows]),
                    "repetitions": _calc_stats([r.get("repetitions") for r in flex_rows], base.get("base_rep_count")),
                },
            }
            return json.dumps(summary, indent=2)
        except Exception as e:
            return f"Error calculating summary: {str(e)}"

    @tool
    def check_compliance_and_outliers(user_id: str, z_score_threshold: float = 2.0) -> str:
        """Analyze a patient's exercise frequency and detect statistical outliers."""
        if not _verify_patient_access(user_id):
            return "Access Denied: You are not authorized to view this patient's data, or the patient does not exist."
        try:
            table_metrics = {
                "grip": ["fsr_palm", "r_fsr_palm"],
                "pinch": ["it", "mt", "r_it", "r_mt"],
                "flexion": ["degree_forward", "degree_backwards", "repetitions"],
            }
            report: Dict[str, Any] = {"user_id": user_id, "exercises": {}}
            now = datetime.now(timezone.utc)

            for table_name, cols in table_metrics.items():
                rows = (
                    client.table(table_name).select("*").eq("user_id", user_id)
                    .order("created_at", desc=False).execute().data
                )
                if not rows:
                    report["exercises"][table_name] = {"status": "No records found"}
                    continue
                timestamps = [
                    datetime.fromisoformat(r["created_at"].replace("Z", "+00:00"))
                    for r in rows if r.get("created_at")
                ]
                timestamps.sort()
                gaps_days = [
                    round((timestamps[i] - timestamps[i - 1]).total_seconds() / 86400, 1)
                    for i in range(1, len(timestamps))
                ]
                days_since_last = round((now - timestamps[-1]).total_seconds() / 86400, 1) if timestamps else None
                outliers = []
                for col in cols:
                    vals = [
                        (r["id"], r.get("session_id"), r.get("created_at"), float(r[col]))
                        for r in rows if r.get(col) is not None
                    ]
                    if len(vals) >= 3:
                        numbers = [v[3] for v in vals]
                        mean = statistics.mean(numbers)
                        stdev = statistics.stdev(numbers)
                        if stdev > 0:
                            for row_id, sess_id, ts, val in vals:
                                z = (val - mean) / stdev
                                if abs(z) >= z_score_threshold:
                                    outliers.append({
                                        "row_id": row_id, "session_id": sess_id, "created_at": ts,
                                        "metric": col, "value": val, "mean": round(mean, 2),
                                        "z_score": round(z, 2),
                                    })
                report["exercises"][table_name] = {
                    "total_records": len(rows),
                    "first_session": timestamps[0].isoformat() if timestamps else None,
                    "last_session": timestamps[-1].isoformat() if timestamps else None,
                    "days_since_last_session": days_since_last,
                    "max_gap_between_sessions_days": max(gaps_days) if gaps_days else 0,
                    "outliers": outliers,
                }
            return json.dumps(report, indent=2)
        except Exception as e:
            return f"Error checking compliance and outliers: {str(e)}"

    @tool
    def compare_exercise_periods(
        user_id: str, period1_start: str, period1_end: str,
        period2_start: str, period2_end: str,
    ) -> str:
        """Compare a patient's average performance metrics between two date periods (ISO format YYYY-MM-DD)."""
        if not _verify_patient_access(user_id):
            return "Access Denied: You are not authorized to view this patient's data, or the patient does not exist."
        try:
            p1 = json.loads(get_patient_exercise_summary.invoke(
                {"user_id": user_id, "start_date": period1_start, "end_date": period1_end}))
            p2 = json.loads(get_patient_exercise_summary.invoke(
                {"user_id": user_id, "start_date": period2_start, "end_date": period2_end}))
            return json.dumps({"user_id": user_id, "period_1": p1, "period_2": p2}, indent=2)
        except Exception as e:
            return f"Error comparing periods: {str(e)}"

    @tool
    def supabase_query(
        table: str,
        user_id: Optional[str] = None,
        session_id: Optional[int] = None,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
        order_by: str = "created_at",
        descending: bool = False,
        limit: int = 50,
    ) -> str:
        """Fetch raw rows from a Supabase table. Requires specifying an authorized patient's user_id."""
        try:
            if table not in READABLE_TABLES:
                return (
                    f"Access Denied: '{table}' is not a readable table. "
                    f"Available: {', '.join(sorted(READABLE_TABLES))}."
                )

            if table in PATIENT_SCOPED_TABLES:
                if not user_id:
                    return "Access Denied: Security policy requires specifying a patient's user_id."
                if not _verify_patient_access(user_id):
                    return "Access Denied: Patient not assigned to you."

            if table == "doctor_patients":
                if user_id and user_id != session.doctor_id:
                    return "Access Denied: Cannot query assignments for other doctors."
                user_id = session.doctor_id

            # Roster only, never the whole directory.
            if table == "profiles":
                rel = (
                    client.table("doctor_patients").select("patient_id")
                    .eq("doctor_id", session.doctor_id).execute()
                )
                allowed = [r["patient_id"] for r in rel.data]
                if user_id and user_id not in allowed:
                    return "Access Denied: Patient not assigned to you."
                ids = [user_id] if user_id else allowed
                if not ids:
                    return json.dumps([])
                return json.dumps(
                    client.table("profiles").select("*").in_("user_id", ids).limit(limit).execute().data,
                    indent=2,
                )

            query = client.table(table).select("*")
            if user_id:
                column = "doctor_id" if table == "doctor_patients" else "user_id"
                query = query.eq(column, user_id)
            if session_id is not None and table in ("grip", "pinch", "flexion"):
                query = query.eq("session_id", session_id)
            if start_date:
                query = query.gte("created_at", start_date)
            norm_end = _normalize_end_date(end_date)
            if norm_end:
                query = query.lte("created_at", norm_end)
            if order_by:
                query = query.order(order_by, desc=descending)
            if limit:
                query = query.limit(limit)

            return json.dumps(query.execute().data, indent=2)
        except Exception as e:
            return f"Error querying Supabase: {str(e)}"

    return [
        find_users_and_rosters,
        get_patient_exercise_summary,
        check_compliance_and_outliers,
        compare_exercise_periods,
        supabase_query,
    ]


rate_limiter = InMemoryRateLimiter(
    requests_per_second=0.25, check_every_n_seconds=0.1, max_bucket_size=2
)

_llm: Optional[ChatOpenAI] = None


# Lazy: the OpenAI client validates credentials on construction, so building it
# at import meant a missing key took the whole module down.
def get_llm() -> ChatOpenAI:
    global _llm
    if _llm is not None:
        return _llm

    api_key = os.getenv("RCAC_API_KEY")
    if not api_key:
        raise RuntimeError("RCAC_API_KEY is not set. Add it to your .env.")

    _llm = ChatOpenAI(
        model=os.getenv("RCAC_MODEL", "gpt-oss:120b"),
        temperature=0,
        api_key=api_key,
        base_url=os.getenv("RCAC_BASE_URL", "https://genai.rcac.purdue.edu/api"),
        rate_limiter=rate_limiter,
    )
    return _llm


def get_system_message(session: DoctorSession) -> str:
    return f"""You are SAM, an intelligent clinical data assistant built for doctors treating Carpal Tunnel Syndrome (CTS).
You are currently authenticated as **Dr. {session.doctor_name}**.

### SECURITY
You can only reach patients formally assigned to Dr. {session.doctor_name}. This is
enforced by the database, not by your own judgement — if a tool returns "Access
Denied", report that plainly rather than trying another route to the same data.

### TOOL SELECTION GUIDELINES
- To see all patients on the roster, call `find_users_and_rosters()` with no arguments.
- For averages, baselines or comparisons, call `get_patient_exercise_summary(user_id=...)`.
- Always prefer the high-level summary tools over `supabase_query`.

### REPORTING
- Measurements are raw 12-bit ADC values from an uncalibrated sensor. Never present
  them as newtons, kilograms or any force unit.
- Prefer change against the patient's baseline to the raw number.
- Do not call a trend from one or two sessions. Say the data is insufficient.

### ANSWER FORMAT
You are rendered in a narrow chat panel, not a document.
- Write prose. No markdown tables, no headings, no bold.
- Lead with names. A patient id is plumbing — give it only if asked, or if two
  patients share a name.
- Short lists go inline: "You have two patients: Alex Rivera and Test Patient."
  Four or more, use "- " bullets, one per line.
- Numbers: round, and say what they are relative to. "Grip is up 40% on
  baseline", not "fsr_palm mean 1400.0".
- Two or three sentences unless asked for detail.
"""


def run_agent(session: DoctorSession, user_input: str, history: List[BaseMessage]) -> AIMessage:
    tools = build_tools(session)
    tools_by_name = {t.name: t for t in tools}
    try:
        model_with_tools = get_llm().bind_tools(tools)
    except RuntimeError as exc:
        return AIMessage(content=f"Error: {exc}")

    for attempt in range(3):
        try:
            messages: List[BaseMessage] = [
                SystemMessage(content=get_system_message(session)),
                *history,
                HumanMessage(content=user_input),
            ]

            for _ in range(10):
                response = model_with_tools.invoke(messages)
                messages.append(response)
                if not response.tool_calls:
                    return response

                for tool_call in response.tool_calls:
                    try:
                        tool_result = tools_by_name[tool_call["name"]].invoke(tool_call["args"])
                    except Exception as tool_err:
                        tool_result = f"Tool execution error: {str(tool_err)}"
                    messages.append(
                        ToolMessage(content=str(tool_result), tool_call_id=tool_call["id"])
                    )

            return AIMessage(content="Error: The agent reached its tool-call limit. Please try again.")
        except Exception as e:
            if "Rate limit exceeded" in str(e) and attempt < 2:
                time.sleep(20 * (attempt + 1))
                continue
            return AIMessage(content=f"Error: {str(e)}\nPlease try rephrasing.")

    return AIMessage(content="Error: Could not complete the request.")


if __name__ == "__main__":
    import getpass

    print("=" * 60)
    print("SAM Agent")
    print("=" * 60)

    email = input("Doctor email: ").strip()
    password = getpass.getpass("Password: ")

    bootstrap = create_client(SUPABASE_URL, SUPABASE_ANON_KEY)
    try:
        auth = bootstrap.auth.sign_in_with_password({"email": email, "password": password})
        sam_session = open_session(auth.session.access_token)
    except Exception as exc:
        print(f"\nLogin failed: {exc}")
        raise SystemExit(1)

    print(f"\nSigned in as Dr. {sam_session.doctor_name}. Ask about your patients.\n")

    chat_history: List[BaseMessage] = []
    while True:
        user_input = input("You: ").strip()
        if user_input.lower() in ("quit", "exit", "q", ""):
            print("Goodbye!")
            break
        print("SAM: ", end="", flush=True)
        reply = run_agent(sam_session, user_input, chat_history)
        print(reply.content)
        chat_history += [HumanMessage(content=user_input), reply]
