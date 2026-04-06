import { supabase, requireAuthOrRedirect, signOutAndRedirect } from "./supabase.js";

const patientsGrid = document.getElementById("patientsGrid");
const emptyState = document.getElementById("emptyState");
const summary = document.getElementById("summary");
const searchInput = document.getElementById("searchInput");
const logoutBtn = document.getElementById("logoutBtn");

await requireAuthOrRedirect();

logoutBtn.addEventListener("click", signOutAndRedirect);

const getRows = async (tableName) => {
  const { data, error } = await supabase.from(tableName).select("user_id, created_at").order("created_at", { ascending: false });
  if (error) {
    console.error(`Failed loading ${tableName}`, error.message);
    return [];
  }
  return data || [];
};

const [baseline, pinch, grip, flexion] = await Promise.all([
  getRows("baseline"),
  getRows("pinch"),
  getRows("grip"),
  getRows("flexion"),
]);

const patientMap = new Map();

[...baseline, ...pinch, ...grip, ...flexion].forEach((entry) => {
  const row = patientMap.get(entry.user_id) || { user_id: entry.user_id, records: 0, lastActivity: null };
  row.records += 1;
  const time = entry.created_at ? new Date(entry.created_at).getTime() : null;
  if (time && (!row.lastActivity || time > row.lastActivity)) row.lastActivity = time;
  patientMap.set(entry.user_id, row);
});

const patients = [...patientMap.values()].sort((a, b) => (b.lastActivity || 0) - (a.lastActivity || 0));
summary.textContent = `${patients.length} patients found from existing rehab data tables.`;

function formatDate(ms) {
  if (!ms) return "No activity timestamp";
  return new Date(ms).toLocaleString();
}

function render(query = "") {
  const filtered = patients.filter((p) => p.user_id.toLowerCase().includes(query.toLowerCase().trim()));

  patientsGrid.innerHTML = "";

  if (!filtered.length) {
    emptyState.classList.remove("hidden");
    return;
  }

  emptyState.classList.add("hidden");

  filtered.forEach((patient) => {
    const card = document.createElement("button");
    card.className = "rounded-xl border border-slate-200 bg-slate-50 p-4 text-left transition hover:border-sky-300 hover:bg-sky-50";
    card.innerHTML = `
      <p class="text-xs uppercase tracking-wide text-slate-500">Patient UUID</p>
      <p class="mt-1 break-all font-mono text-sm">${patient.user_id}</p>
      <p class="mt-3 text-sm text-slate-600">Records: <span class="font-semibold text-slate-900">${patient.records}</span></p>
      <p class="text-xs text-slate-500 mt-1">Last activity: ${formatDate(patient.lastActivity)}</p>
    `;

    card.addEventListener("click", () => {
      window.location.href = `dashboard.html?patient=${encodeURIComponent(patient.user_id)}`;
    });

    patientsGrid.appendChild(card);
  });
}

searchInput.addEventListener("input", (e) => render(e.target.value));
render();
