import { supabase, requireAuthOrRedirect, signOutAndRedirect, getCurrentUser } from "./supabase.js";
import {
  formatForce, formatAngle, formatChange, formatOfBaseline, formatDate,
  trendVerdict, adherence, exertionScore, toCsv, downloadCsv,
} from "./insights.js?v=2";

await requireAuthOrRedirect();
const currentUser = await getCurrentUser();
document.getElementById("logoutBtn").addEventListener("click", signOutAndRedirect);

const params = new URLSearchParams(window.location.search);
const patientId = params.get("patient");
const patientNameParam = params.get("name");

if (!patientId) window.location.href = "patients.html";

document.getElementById("patientName").textContent = patientNameParam || "Patient";
document.getElementById("patientMeta").textContent = patientId;

const rangeSelect = document.getElementById("rangeSelect");
const charts = {};

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

function sinceIso(days) {
  if (!days) return null;
  const d = new Date();
  d.setDate(d.getDate() - days);
  return d.toISOString();
}

async function fetchTable(table, since) {
  let q = supabase.from(table).select("*").eq("user_id", patientId)
    .order("created_at", { ascending: true });
  if (since) q = q.gte("created_at", since);
  const { data, error } = await q;
  if (error) {
    console.error(`Failed loading ${table}:`, error.message);
    return [];
  }
  return data || [];
}

async function fetchAdherence(days) {
  let q = supabase.from("pt_sessions").select("exercise_id, completed_on")
    .eq("user_id", patientId);
  if (days) {
    const d = new Date();
    d.setDate(d.getDate() - days);
    q = q.gte("completed_on", d.toISOString().slice(0, 10));
  }
  const { data, error } = await q;
  if (error) {
    // Expected until db/05 is applied; the panel says so rather than vanishing.
    console.warn("pt_sessions unavailable:", error.message);
    return null;
  }
  return data || [];
}

async function fetchNotes() {
  const { data, error } = await supabase.from("patient_notes")
    .select("id, body, created_at")
    .eq("patient_id", patientId)
    .order("created_at", { ascending: false });
  if (error) {
    console.warn("patient_notes unavailable:", error.message);
    return null;
  }
  return data || [];
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

const TONE = {
  good: "text-emerald-700 bg-emerald-50 border-emerald-200",
  bad: "text-rose-700 bg-rose-50 border-rose-200",
  flat: "text-amber-700 bg-amber-50 border-amber-200",
  unknown: "text-slate-600 bg-slate-50 border-slate-200",
};

function summaryCard({ label, value, sub, tone = "unknown" }) {
  const el = document.createElement("div");
  el.className = "rounded-xl border border-slate-200 bg-white p-4";
  el.innerHTML = `
    <p class="text-xs font-medium uppercase tracking-wide text-slate-500">${label}</p>
    <p class="mt-1.5 text-2xl font-bold tabular-nums">${value}</p>
    <p class="mt-1 inline-block rounded border px-1.5 py-0.5 text-xs ${TONE[tone]}">${sub}</p>
  `;
  return el;
}

function renderSummary({ grip, pinch, flexion, baseline, adh }) {
  const host = document.getElementById("summaryCards");
  host.innerHTML = "";

  // Adherence first: it is the question a clinician opens with, and it is the
  // one the sensors cannot answer.
  if (adh === null) {
    host.appendChild(summaryCard({
      label: "Adherence", value: "—",
      sub: "Run db/05 to enable", tone: "unknown",
    }));
  } else {
    const tone = adh.percent >= 70 ? "good" : adh.percent >= 40 ? "flat" : "bad";
    host.appendChild(summaryCard({
      label: "Adherence", value: `${adh.percent}%`,
      sub: `${adh.activeDays} of ${adh.totalDays} days active`, tone,
    }));
  }

  const latestGrip = grip.at(-1);
  const gripVerdict = trendVerdict(grip.map((r) => r.fsr_palm));
  host.appendChild(summaryCard({
    label: "Grip strength",
    value: latestGrip ? formatForce(latestGrip.fsr_palm) : "—",
    sub: latestGrip?.r_fsr_palm
      ? `${formatChange(latestGrip.r_fsr_palm)} vs baseline · ${gripVerdict.label}`
      : gripVerdict.label,
    tone: gripVerdict.tone,
  }));

  const latestPinch = pinch.at(-1);
  const pinchVerdict = trendVerdict(pinch.map((r) => r.it));
  host.appendChild(summaryCard({
    label: "Pinch (index–thumb)",
    value: latestPinch ? formatForce(latestPinch.it) : "—",
    sub: latestPinch?.r_it
      ? `${formatChange(latestPinch.r_it)} vs baseline · ${pinchVerdict.label}`
      : pinchVerdict.label,
    tone: pinchVerdict.tone,
  }));

  const latestFlex = flexion.at(-1);
  const flexVerdict = trendVerdict(flexion.map((r) => r.degree_forward));
  const baseFlex = baseline?.base_flex_deg;
  host.appendChild(summaryCard({
    label: "Wrist flexion",
    value: latestFlex ? formatAngle(latestFlex.degree_forward) : "—",
    sub: baseFlex
      ? `baseline ${formatAngle(baseFlex)} · ${flexVerdict.label}`
      : `${flexVerdict.label} · no baseline recorded`,
    tone: flexVerdict.tone,
  }));
}

function renderTrendLine(id, verdict) {
  const el = document.getElementById(id);
  el.className = `mb-3 text-xs ${
    verdict.tone === "good" ? "text-emerald-700"
      : verdict.tone === "bad" ? "text-rose-700"
      : verdict.tone === "flat" ? "text-amber-700" : "text-slate-500"}`;
  el.textContent = verdict.detail ? `${verdict.label} — ${verdict.detail}` : verdict.label;
}

function renderChart(canvasId, emptyId, labels, datasets, verdict) {
  const canvas = document.getElementById(canvasId);
  const empty = document.getElementById(emptyId);

  // One point is not a line. Drawing it produces a chart that looks broken
  // rather than one that looks empty.
  if (labels.length < 2) {
    canvas.classList.add("hidden");
    empty.classList.remove("hidden");
    empty.textContent = labels.length === 0
      ? "No sessions in this range."
      : "One session recorded. A second is needed before a trend can be drawn.";
    return;
  }

  canvas.classList.remove("hidden");
  empty.classList.add("hidden");
  charts[canvasId]?.destroy();
  charts[canvasId] = new Chart(canvas, {
    type: "line",
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: { legend: { display: datasets.length > 1, labels: { boxWidth: 10, font: { size: 11 } } } },
      scales: {
        y: { beginAtZero: false, ticks: { font: { size: 11 } }, grid: { color: "#f1f5f9" } },
        x: { ticks: { font: { size: 11 }, maxRotation: 0, autoSkipPadding: 16 }, grid: { display: false } },
      },
    },
  });
  if (verdict) renderTrendLine(verdict.id, verdict.value);
}

function renderAdherence(adh) {
  const strip = document.getElementById("adherenceStrip");
  const summary = document.getElementById("adherenceSummary");
  strip.innerHTML = "";

  if (adh === null) {
    summary.textContent = "Not available";
    strip.innerHTML = `<p class="text-sm text-slate-500">
      Exercise tracking needs <code class="rounded bg-slate-100 px-1">db/05_adherence_and_exertion.sql</code>.</p>`;
    return;
  }

  summary.textContent = `${adh.activeDays} of ${adh.totalDays} days · ${adh.percent}%`;
  for (const day of adh.strip) {
    const sq = document.createElement("div");
    sq.className = `h-4 w-4 rounded-sm ${day.active ? "bg-emerald-500" : "bg-slate-200"}`;
    sq.title = `${day.date}${day.active ? " — completed" : " — nothing recorded"}`;
    strip.appendChild(sq);
  }
}

function renderNotes(notes) {
  const host = document.getElementById("notesList");
  host.innerHTML = "";

  if (notes === null) {
    host.innerHTML = `<p class="text-sm text-slate-500">
      Notes need <code class="rounded bg-slate-100 px-1">db/06_clinician_notes.sql</code>.</p>`;
    document.getElementById("noteForm").classList.add("hidden");
    return;
  }
  if (notes.length === 0) {
    host.innerHTML = `<p class="text-sm text-slate-500">No notes yet.</p>`;
    return;
  }
  for (const n of notes) {
    const el = document.createElement("div");
    el.className = "rounded-lg border border-slate-200 bg-slate-50 p-3";
    el.innerHTML = `
      <p class="whitespace-pre-wrap text-sm">${n.body.replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]))}</p>
      <p class="mt-1.5 text-xs text-slate-500">${new Date(n.created_at).toLocaleString()}</p>
    `;
    host.appendChild(el);
  }
}

function renderActivity(rows) {
  const body = document.getElementById("activityBody");
  document.getElementById("logCount").textContent = `${rows.length} session${rows.length === 1 ? "" : "s"}`;
  body.innerHTML = rows.length
    ? rows.map((r) => `
        <tr>
          <td class="whitespace-nowrap px-4 py-2">${formatDate(r.ts)}</td>
          <td class="px-4 py-2">${r.type}</td>
          <td class="px-4 py-2 tabular-nums">${r.result}</td>
          <td class="px-4 py-2 tabular-nums">${r.change ?? "—"}</td>
          <td class="px-4 py-2 tabular-nums">${r.bpm ?? "—"}</td>
        </tr>`).join("")
    : `<tr><td colspan="5" class="px-4 py-4 text-slate-500">No sessions in this range.</td></tr>`;
}

// ---------------------------------------------------------------------------
// Load
// ---------------------------------------------------------------------------

let lastLoad = { activity: [] };

async function load() {
  const days = Number(rangeSelect.value);
  const since = sinceIso(days);

  const [baselineRows, pinch, grip, flexion, adhRows, notes] = await Promise.all([
    fetchTable("baseline", null), // baseline is a fixed reference, never range-filtered
    fetchTable("pinch", since),
    fetchTable("grip", since),
    fetchTable("flexion", since),
    fetchAdherence(days || 365),
    fetchNotes(),
  ]);

  const baseline = baselineRows.at(-1) || null;
  const adh = adhRows === null ? null : adherence(adhRows, days || 365);

  renderSummary({ grip, pinch, flexion, baseline, adh });
  renderAdherence(adh);
  renderNotes(notes);

  const label = (r) => formatDate(r.created_at);

  renderChart("gripChart", "gripEmpty", grip.map(label), [{
    label: "Grip", data: grip.map((r) => r.fsr_palm),
    borderColor: "#0ea5e9", backgroundColor: "#0ea5e922", fill: true, tension: 0.3,
  }], { id: "gripTrend", value: trendVerdict(grip.map((r) => r.fsr_palm)) });

  renderChart("pinchChart", "pinchEmpty", pinch.map(label), [
    { label: "Index–thumb", data: pinch.map((r) => r.it), borderColor: "#0f766e", tension: 0.3 },
    { label: "Middle–thumb", data: pinch.map((r) => r.mt), borderColor: "#7dd3fc", tension: 0.3 },
  ], { id: "pinchTrend", value: trendVerdict(pinch.map((r) => r.it)) });

  renderChart("flexionChart", "flexionEmpty", flexion.map(label), [
    { label: "Forward", data: flexion.map((r) => r.degree_forward), borderColor: "#1d4ed8", tension: 0.3 },
    { label: "Backward", data: flexion.map((r) => r.degree_backwards), borderColor: "#93c5fd", tension: 0.3 },
  ], { id: "flexionTrend", value: trendVerdict(flexion.map((r) => r.degree_forward)) });

  const resting = baseline?.base_bpm_rest;
  const exertionSeries = grip.map((r) => exertionScore(r, resting));
  const haveExertion = exertionSeries.filter((v) => v !== null);
  if (haveExertion.length === 0) {
    document.getElementById("exertionChart").classList.add("hidden");
    const empty = document.getElementById("exertionEmpty");
    empty.classList.remove("hidden");
    empty.textContent = resting
      ? "No sessions yet with a heart-rate reading."
      : "Needs a resting heart rate on the patient's baseline.";
    renderTrendLine("exertionTrend", { label: "Not available", tone: "unknown", detail: "" });
  } else {
    renderChart("exertionChart", "exertionEmpty", grip.map(label), [{
      label: "% of baseline effort", data: exertionSeries,
      borderColor: "#9333ea", backgroundColor: "#9333ea22", fill: true, tension: 0.3, spanGaps: true,
    }], { id: "exertionTrend", value: trendVerdict(haveExertion) });
  }

  const activity = [
    ...grip.map((r) => ({ ts: r.created_at, type: "Grip", result: formatForce(r.fsr_palm),
      change: formatChange(r.r_fsr_palm), bpm: r.bpm_avg })),
    ...pinch.map((r) => ({ ts: r.created_at, type: "Pinch", result: `IT ${formatForce(r.it)} · MT ${formatForce(r.mt)}`,
      change: formatChange(r.r_it), bpm: r.bpm_avg })),
    ...flexion.map((r) => ({ ts: r.created_at, type: "Flexion",
      result: `${formatAngle(r.degree_forward)} fwd · ${formatAngle(r.degree_backwards)} back`,
      change: `${r.repetitions ?? "—"} reps`, bpm: null })),
  ].sort((a, b) => new Date(b.ts) - new Date(a.ts));

  renderActivity(activity);
  lastLoad = { activity };
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

rangeSelect.addEventListener("change", load);

document.getElementById("exportBtn").addEventListener("click", () => {
  const csv = toCsv(
    ["Date", "Type", "Result", "vs baseline", "Heart rate (bpm)"],
    lastLoad.activity.map((r) => [formatDate(r.ts), r.type, r.result, r.change ?? "", r.bpm ?? ""]),
  );
  const safeName = (patientNameParam || patientId).replace(/[^a-z0-9]+/gi, "-").toLowerCase();
  downloadCsv(`mind-cts-${safeName}-${new Date().toISOString().slice(0, 10)}.csv`, csv);
});

document.getElementById("noteForm").addEventListener("submit", async (e) => {
  e.preventDefault();
  const field = document.getElementById("noteBody");
  const body = field.value.trim();
  if (!body || !currentUser) return;

  const { error } = await supabase.from("patient_notes").insert({
    doctor_id: currentUser.id, patient_id: patientId, body,
  });
  if (error) {
    alert(`Could not save note: ${error.message}`);
    return;
  }
  field.value = "";
  renderNotes(await fetchNotes());
});

await load();
