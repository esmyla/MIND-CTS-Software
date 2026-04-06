import { supabase, requireAuthOrRedirect, signOutAndRedirect } from "./supabase.js";

await requireAuthOrRedirect();

document.getElementById("logoutBtn").addEventListener("click", signOutAndRedirect);

const params = new URLSearchParams(window.location.search);
const patientId = params.get("patient");
const patientName = params.get("name");

if (!patientId) {
  window.location.href = "patients.html";
}

document.getElementById("patientIdText").textContent = patientName
  ? `Patient: ${patientName} • ${patientId}`
  : `Patient: ${patientId}`;

const { data: meData } = await supabase.auth.getUser();
const me = meData?.user;
if (me) {
  const { data: assignment, error: assignmentError } = await supabase
    .from("doctor_patients")
    .select("patient_id")
    .eq("doctor_id", me.id)
    .eq("patient_id", patientId)
    .limit(1);

  if (assignmentError || !assignment || assignment.length === 0) {
    window.location.href = "patients.html";
  }
}

const [baselineRes, pinchRes, gripRes, flexionRes] = await Promise.all([
  supabase.from("baseline").select("*").eq("user_id", patientId).order("created_at", { ascending: true }).limit(1),
  supabase.from("pinch").select("*").eq("user_id", patientId).order("created_at", { ascending: true }),
  supabase.from("grip").select("*").eq("user_id", patientId).order("created_at", { ascending: true }),
  supabase.from("flexion").select("*").eq("user_id", patientId).order("created_at", { ascending: true }),
]);

const baseline = baselineRes.data?.[0] || null;
const pinchRows = pinchRes.data || [];
const gripRows = gripRes.data || [];
const flexionRows = flexionRes.data || [];

const kpiCards = document.getElementById("kpiCards");

const latestPinch = pinchRows.at(-1);
const latestGrip = gripRows.at(-1);
const latestFlexion = flexionRows.at(-1);

const kpis = [
  {
    label: "Latest Pinch IT",
    value: latestPinch?.it != null ? latestPinch.it.toFixed(2) : "—",
    subtitle: baseline?.base_it != null ? `Baseline: ${baseline.base_it.toFixed(2)}` : "No baseline",
  },
  {
    label: "Latest Pinch MT",
    value: latestPinch?.mt != null ? latestPinch.mt.toFixed(2) : "—",
    subtitle: baseline?.base_mt != null ? `Baseline: ${baseline.base_mt.toFixed(2)}` : "No baseline",
  },
  {
    label: "Latest Grip",
    value: latestGrip?.fsr_palm != null ? latestGrip.fsr_palm.toFixed(2) : "—",
    subtitle: baseline?.base_grip != null ? `Baseline: ${baseline.base_grip.toFixed(2)}` : "No baseline",
  },
  {
    label: "Latest Flexion Forward",
    value: latestFlexion?.degree_forward != null ? `${latestFlexion.degree_forward}°` : "—",
    subtitle: baseline?.base_flex_deg != null ? `Baseline: ${baseline.base_flex_deg}°` : "No baseline",
  },
];

kpis.forEach((kpi) => {
  const card = document.createElement("div");
  card.className = "rounded-xl border border-slate-200 bg-white p-4";
  card.innerHTML = `
    <p class="text-sm text-slate-500">${kpi.label}</p>
    <p class="mt-2 text-2xl font-bold text-slate-900">${kpi.value}</p>
    <p class="mt-1 text-xs text-slate-500">${kpi.subtitle}</p>
  `;
  kpiCards.appendChild(card);
});

const activity = [
  ...pinchRows.map((row) => ({
    ts: row.created_at,
    session_id: row.session_id,
    type: "Pinch",
    details: `IT ${row.it ?? "—"}, MT ${row.mt ?? "—"}, R-IT ${row.r_it ?? "—"}, R-MT ${row.r_mt ?? "—"}`,
  })),
  ...gripRows.map((row) => ({
    ts: row.created_at,
    session_id: row.session_id,
    type: "Grip",
    details: `Palm ${row.fsr_palm ?? "—"}, R-Palm ${row.r_fsr_palm ?? "—"}`,
  })),
  ...flexionRows.map((row) => ({
    ts: row.created_at,
    session_id: row.session_id,
    type: "Flexion",
    details: `Forward ${row.degree_forward ?? "—"}°, Backward ${row.degree_backwards ?? "—"}°, Reps ${row.repetitions ?? "—"}`,
  })),
].sort((a, b) => new Date(b.ts) - new Date(a.ts));

const activityBody = document.getElementById("activityBody");
if (!activity.length) {
  activityBody.innerHTML = `<tr><td colspan="4" class="px-3 py-3 text-slate-500">No activity recorded for this patient.</td></tr>`;
} else {
  activityBody.innerHTML = activity
    .map(
      (row) => `
      <tr>
        <td class="px-3 py-2 whitespace-nowrap">${new Date(row.ts).toLocaleString()}</td>
        <td class="px-3 py-2">${row.session_id ?? "—"}</td>
        <td class="px-3 py-2">${row.type}</td>
        <td class="px-3 py-2">${row.details}</td>
      </tr>`,
    )
    .join("");
}

function renderLineChart(canvasId, labels, values, label, color) {
  new Chart(document.getElementById(canvasId), {
    type: "line",
    data: {
      labels,
      datasets: [
        {
          label,
          data: values,
          borderColor: color,
          backgroundColor: `${color}22`,
          fill: true,
          tension: 0.35,
        },
      ],
    },
    options: {
      responsive: true,
      plugins: { legend: { display: true } },
      scales: { y: { beginAtZero: true } },
    },
  });
}

renderLineChart(
  "pinchChart",
  pinchRows.map((r) => new Date(r.created_at).toLocaleDateString()),
  pinchRows.map((r) => r.it),
  "Pinch IT Trend",
  "#0ea5e9",
);

renderLineChart(
  "gripChart",
  gripRows.map((r) => new Date(r.created_at).toLocaleDateString()),
  gripRows.map((r) => r.fsr_palm),
  "Grip Trend",
  "#1d4ed8",
);

renderLineChart(
  "flexionChart",
  flexionRows.map((r) => new Date(r.created_at).toLocaleDateString()),
  flexionRows.map((r) => r.degree_forward),
  "Forward Flexion Trend",
  "#64748b",
);

const sessions = [...pinchRows, ...gripRows, ...flexionRows].reduce((acc, row) => {
  const key = row.session_id ?? "N/A";
  acc.set(key, (acc.get(key) || 0) + 1);
  return acc;
}, new Map());

new Chart(document.getElementById("sessionChart"), {
  type: "bar",
  data: {
    labels: [...sessions.keys()],
    datasets: [
      {
        label: "Events per Session",
        data: [...sessions.values()],
        backgroundColor: "#38bdf8",
      },
    ],
  },
  options: { responsive: true, plugins: { legend: { display: true } } },
});
