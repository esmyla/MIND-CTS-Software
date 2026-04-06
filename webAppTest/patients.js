import { supabase, requireAuthOrRedirect, signOutAndRedirect, getCurrentUser } from "./supabase.js";

const allPatientsGrid = document.getElementById("allPatientsGrid");
const assignedGrid = document.getElementById("assignedGrid");
const allEmptyState = document.getElementById("allEmptyState");
const assignedEmptyState = document.getElementById("assignedEmptyState");
const setupNotice = document.getElementById("setupNotice");
const summary = document.getElementById("summary");
const searchInput = document.getElementById("searchInput");
const logoutBtn = document.getElementById("logoutBtn");

await requireAuthOrRedirect();
const currentUser = await getCurrentUser();

logoutBtn.addEventListener("click", signOutAndRedirect);

let allPatients = [];
let assignedPatients = new Set();

function showSetupNotice(message) {
  setupNotice.textContent = message;
  setupNotice.classList.remove("hidden");
}

function normalize(text) {
  return (text || "").toLowerCase();
}

function patientMatchesQuery(patient, query) {
  const q = normalize(query.trim());
  if (!q) return true;

  return [patient.full_name, patient.email, patient.user_id].some((field) => normalize(field).includes(q));
}

function patientCard(patient, isAssigned) {
  const wrapper = document.createElement("div");
  wrapper.className = "rounded-xl border border-slate-200 bg-slate-50 p-4";

  const openBtn = `<button data-action="open" data-id="${patient.user_id}" class="rounded-md bg-sky-600 px-3 py-1.5 text-xs font-semibold text-white hover:bg-sky-700">Open Dashboard</button>`;
  const assignBtn = isAssigned
    ? `<button data-action="unassign" data-id="${patient.user_id}" class="rounded-md border border-rose-300 bg-white px-3 py-1.5 text-xs font-semibold text-rose-700 hover:bg-rose-50">Unassign</button>`
    : `<button data-action="assign" data-id="${patient.user_id}" class="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 hover:bg-slate-100">Assign</button>`;

  wrapper.innerHTML = `
    <p class="text-base font-semibold text-slate-900">${patient.full_name || "Unnamed Patient"}</p>
    <p class="mt-1 text-xs text-slate-600">${patient.email || "No email"}</p>
    <p class="mt-1 break-all font-mono text-xs text-slate-500">${patient.user_id}</p>
    <div class="mt-3 flex flex-wrap gap-2">${openBtn}${assignBtn}</div>
  `;

  wrapper.querySelectorAll("button").forEach((button) => {
    button.addEventListener("click", async () => {
      const action = button.dataset.action;
      const userId = button.dataset.id;

      if (action === "open") {
        window.location.href = `dashboard.html?patient=${encodeURIComponent(userId)}&name=${encodeURIComponent(patient.full_name || "")}`;
        return;
      }

      if (!currentUser) return;

      if (action === "assign") {
        const { error } = await supabase.from("doctor_patients").upsert(
          {
            doctor_id: currentUser.id,
            patient_id: userId,
          },
          { onConflict: "doctor_id,patient_id" },
        );

        if (error) {
          showSetupNotice(`Assignment failed: ${error.message}`);
          return;
        }

        assignedPatients.add(userId);
      }

      if (action === "unassign") {
        const { error } = await supabase
          .from("doctor_patients")
          .delete()
          .eq("doctor_id", currentUser.id)
          .eq("patient_id", userId);

        if (error) {
          showSetupNotice(`Unassign failed: ${error.message}`);
          return;
        }

        assignedPatients.delete(userId);
      }

      render(searchInput.value);
    });
  });

  return wrapper;
}

async function loadPatientsFromProfiles() {
  const { data, error } = await supabase
    .from("profiles")
    .select("user_id, full_name, email, role")
    .eq("role", "patient")
    .order("full_name", { ascending: true });

  if (error) {
    showSetupNotice(
      `Could not load patient directory by name (${error.message}). Run webAppTest/sql/doctor_portal_setup.sql and ensure RLS policies permit doctor reads.`,
    );
    return [];
  }

  return data || [];
}

async function loadAssignedPatients() {
  if (!currentUser) return new Set();

  const { data, error } = await supabase
    .from("doctor_patients")
    .select("patient_id")
    .eq("doctor_id", currentUser.id);

  if (error) {
    showSetupNotice(
      `Could not load assignments (${error.message}). Run webAppTest/sql/doctor_portal_setup.sql and ensure policy allows doctor assignment reads.`,
    );
    return new Set();
  }

  return new Set((data || []).map((row) => row.patient_id));
}

function render(query = "") {
  const filtered = allPatients.filter((p) => patientMatchesQuery(p, query));
  const assigned = filtered.filter((p) => assignedPatients.has(p.user_id));

  summary.textContent = `${allPatients.length} patient profiles available. ${assignedPatients.size} assigned to you.`;

  allPatientsGrid.innerHTML = "";
  assignedGrid.innerHTML = "";

  if (!filtered.length) allEmptyState.classList.remove("hidden");
  else allEmptyState.classList.add("hidden");

  if (!assigned.length) assignedEmptyState.classList.remove("hidden");
  else assignedEmptyState.classList.add("hidden");

  filtered.forEach((patient) => allPatientsGrid.appendChild(patientCard(patient, assignedPatients.has(patient.user_id))));
  assigned.forEach((patient) => assignedGrid.appendChild(patientCard(patient, true)));
}

allPatients = await loadPatientsFromProfiles();
assignedPatients = await loadAssignedPatients();

searchInput.addEventListener("input", (e) => render(e.target.value));
render();
