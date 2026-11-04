import os
import time
import json
import random
import string
import statistics
import supabase
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from langchain_core.messages import HumanMessage, AIMessage, BaseMessage, SystemMessage, ToolMessage
from langchain_core.tools import tool
from langchain_core.rate_limiters import InMemoryRateLimiter

load_dotenv()

# ==========================================
# AUTHENTICATION & SESSION STATE
# ==========================================
# In the real app, this will be populated by the JWT / session token of the logged-in user.
CURRENT_DOCTOR = {
    "user_id": None,
    "full_name": None,
    "email": None
}

def _get_client():
    url = os.getenv("SUPABASE_PROJECT_ID")
    key = os.getenv("SUPABASE_SECRET_KEY") or os.getenv("SUPABASE_PUBLIC_KEY")
    if not url or not key:
        raise ValueError("Missing SUPABASE_PROJECT_ID or SUPABASE_SECRET_KEY in .env")
    return supabase.create_client(url, key)


def _verify_patient_access(patient_id: str) -> bool:
    """Security check: verify the patient belongs to the currently authenticated doctor."""
    if not CURRENT_DOCTOR["user_id"]:
        return False
    client = _get_client()
    resp = client.table("doctor_patients").select("id").eq("doctor_id", CURRENT_DOCTOR["user_id"]).eq("patient_id", patient_id).execute()
    return len(resp.data) > 0


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


# -------- Tools --------
@tool
def find_users_and_rosters(name_or_email: Optional[str] = None) -> str:
    """
    Search for your assigned patients by partial name or email. 
    If left blank, returns a list of ALL your assigned patients.
    """
    try:
        doctor_id = CURRENT_DOCTOR["user_id"]
        if not doctor_id:
            return "Error: No doctor authenticated."

        client = _get_client()
        
        # 1. Get ONLY the patients assigned to this doctor
        rel_resp = client.table("doctor_patients").select("patient_id").eq("doctor_id", doctor_id).execute()
        patient_ids = [row["patient_id"] for row in rel_resp.data]
        
        if not patient_ids:
            return json.dumps({"assigned_patients": []})

        # 2. Filter profiles to only those authorized patients
        query = client.table("profiles").select("*").in_("user_id", patient_ids)
        if name_or_email:
            clean_term = name_or_email.strip()
            query = query.or_(f"full_name.ilike.%{clean_term}%,email.ilike.%{clean_term}%")

        response = query.execute()
        return json.dumps(response.data, indent=2)
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
        client = _get_client()
        norm_end = _normalize_end_date(end_date)
        base_resp = client.table("baseline").select("*").eq("user_id", user_id).order("created_at", desc=True).limit(1).execute()
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
        client = _get_client()
        table_metrics = {
            "grip": ["fsr_palm", "r_fsr_palm"],
            "pinch": ["it", "mt", "r_it", "r_mt"],
            "flexion": ["degree_forward", "degree_backwards", "repetitions"],
        }
        report: Dict[str, Any] = {"user_id": user_id, "exercises": {}}
        now = datetime.now(timezone.utc)

        for table_name, cols in table_metrics.items():
            rows = client.table(table_name).select("*").eq("user_id", user_id).order("created_at", desc=False).execute().data
            if not rows:
                report["exercises"][table_name] = {"status": "No records found"}
                continue
            timestamps = [datetime.fromisoformat(r["created_at"].replace("Z", "+00:00")) for r in rows if r.get("created_at")]
            timestamps.sort()
            gaps_days = [round((timestamps[i] - timestamps[i - 1]).total_seconds() / 86400, 1) for i in range(1, len(timestamps))]
            days_since_last = round((now - timestamps[-1]).total_seconds() / 86400, 1) if timestamps else None
            outliers = []
            for col in cols:
                vals = [(r["id"], r.get("session_id"), r.get("created_at"), float(r[col])) for r in rows if r.get(col) is not None]
                if len(vals) >= 3:
                    numbers = [v[3] for v in vals]
                    mean = statistics.mean(numbers)
                    stdev = statistics.stdev(numbers)
                    if stdev > 0:
                        for row_id, sess_id, ts, val in vals:
                            z = (val - mean) / stdev
                            if abs(z) >= z_score_threshold:
                                outliers.append({"row_id": row_id, "session_id": sess_id, "created_at": ts, "metric": col, "value": val, "mean": round(mean, 2), "z_score": round(z, 2)})
            report["exercises"][table_name] = {
                "total_records": len(rows), "first_session": timestamps[0].isoformat() if timestamps else None,
                "last_session": timestamps[-1].isoformat() if timestamps else None, "days_since_last_session": days_since_last,
                "max_gap_between_sessions_days": max(gaps_days) if gaps_days else 0, "outliers": outliers,
            }
        return json.dumps(report, indent=2)
    except Exception as e:
        return f"Error checking compliance and outliers: {str(e)}"


@tool
def compare_exercise_periods(user_id: str, period1_start: str, period1_end: str, period2_start: str, period2_end: str) -> str:
    """Compare a patient's average performance metrics between two date periods (ISO format YYYY-MM-DD)."""
    if not _verify_patient_access(user_id):
        return "Access Denied: You are not authorized to view this patient's data, or the patient does not exist."
    try:
        p1 = json.loads(get_patient_exercise_summary.invoke({"user_id": user_id, "start_date": period1_start, "end_date": period1_end}))
        p2 = json.loads(get_patient_exercise_summary.invoke({"user_id": user_id, "start_date": period2_start, "end_date": period2_end}))
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
        if table in ["baseline", "grip", "pinch", "flexion"]:
            if not user_id:
                return "Access Denied: Security policy requires specifying a patient's user_id."
            if not _verify_patient_access(user_id):
                return "Access Denied: Patient not assigned to you."
                
        if table == "doctor_patients":
            # Force query to only show the logged-in doctor's records
            if user_id and user_id != CURRENT_DOCTOR["user_id"]:
                 return "Access Denied: Cannot query assignments for other doctors."
            user_id = CURRENT_DOCTOR["user_id"] # Safe override

        client = _get_client()
        query = client.table(table).select("*")

        if user_id:
            if table == "doctor_patients":
                query = query.eq("doctor_id", user_id)
            else:
                query = query.eq("user_id", user_id)

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

        response = query.execute()
        return json.dumps(response.data, indent=2)
    except Exception as e:
        return f"Error querying Supabase: {str(e)}"


TOOLS = [find_users_and_rosters, get_patient_exercise_summary, check_compliance_and_outliers, compare_exercise_periods, supabase_query]

rate_limiter = InMemoryRateLimiter(requests_per_second=0.25, check_every_n_seconds=0.1, max_bucket_size=2)
llm = ChatOpenAI(model=os.getenv("RCAC_MODEL", "gpt-oss:120b"), temperature=0, api_key=os.getenv("RCAC_API_KEY"), base_url="https://genai.rcac.purdue.edu/api", rate_limiter=rate_limiter)


def get_system_message() -> str:
    doc_name = CURRENT_DOCTOR.get('full_name') or "Unknown"
    return f"""You are SAM, an intelligent clinical data assistant built for doctors treating Carpal Tunnel Syndrome (CTS).
You are currently authenticated as **Dr. {doc_name}**.

### SECURITY PROTOCOL
You operate in a strictly isolated environment. You ONLY have access to patients who are formally assigned to Dr. {doc_name} via the `doctor_patients` table. 
If asked about a patient, you must check if they belong to Dr. {doc_name}. If a tool returns "Access Denied", inform the doctor that the patient is not on their roster.

### TOOL SELECTION GUIDELINES
- To see all patients on Dr. {doc_name}'s roster, call `find_users_and_rosters()` with no arguments.
- For overall exercise data, averages, or comparisons against baseline, call `get_patient_exercise_summary(user_id=...)`.
- Always prefer the high-level summary tools over `supabase_query`.
"""

def run_agent(user_input: str, history: List[BaseMessage]) -> AIMessage:
    for attempt in range(3):
        try:
            messages = [SystemMessage(content=get_system_message()), *history, HumanMessage(content=user_input)]
            tools_by_name = {t.name: t for t in TOOLS}
            model_with_tools = llm.bind_tools(TOOLS)

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
                    messages.append(ToolMessage(content=str(tool_result), tool_call_id=tool_call["id"]))

            return AIMessage(content="Error: The agent reached its tool-call limit. Please try again.")
        except Exception as e:
            if "Rate limit exceeded" in str(e) and attempt < 2:
                time.sleep(20 * (attempt + 1))
                continue
            return AIMessage(content=f"Error: {str(e)}\nPlease try rephrasing.")


if __name__ == "__main__":
    print("=" * 60)
    print("SAM Agent (Secure Clinical Environment)")
    print("=" * 60)
    
    history: List[BaseMessage] = []

    while True:
        # === LOGIN INTERCEPT (Development Only) ===
        if not CURRENT_DOCTOR["user_id"]:
            print("\n[SECURITY] Unauthenticated Session.")
            email_input = input("Please enter your doctor email to log in (or 'quit'): ").strip()
            
            if email_input.lower() in ['quit', 'exit', 'q']:
                print("Goodbye!")
                break
            if not email_input:
                continue
                
            try:
                client = _get_client()
                resp = client.table("profiles").select("*").eq("email", email_input).eq("role", "doctor").execute()
                if resp.data:
                    doc_data = resp.data[0]
                    CURRENT_DOCTOR["user_id"] = doc_data["user_id"]
                    CURRENT_DOCTOR["full_name"] = doc_data["full_name"]
                    CURRENT_DOCTOR["email"] = doc_data["email"]
                    print(f"\n✅ Authentication successful. Welcome, Dr. {doc_data['full_name']}!")
                    print("You can now query your assigned patients' data. Ask me anything.")
                else:
                    print(f"\n❌ Login Failed: No doctor account found with email '{email_input}'.")
            except Exception as e:
                print(f"\n⚠️ Database Error during login: {e}")
                print("Make sure you added SUPABASE_SECRET_KEY to your .env file.")
            continue
        # ==========================================

        user_input = input("\nYou: ").strip()

        if user_input.lower() in ['quit', 'exit', 'q', ""]:
            print("Goodbye!")
            break

        print("Agent: ", end="", flush=True)
        response = run_agent(user_input, history)
        print(response.content)
        
        history += [HumanMessage(content=user_input), response]