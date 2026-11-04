import { supabase } from "./supabase.js";

const SAM_URL = window.SAM_URL || "http://localhost:8700";

const panel = document.getElementById("samPanel");
const log = document.getElementById("samLog");
const form = document.getElementById("samForm");
const input = document.getElementById("samInput");
const sendBtn = document.getElementById("samSend");
const status = document.getElementById("samStatus");

// Kept client-side so SAM stays stateless across restarts.
const history = [];

function bubble(role, text, { pending = false } = {}) {
  const row = document.createElement("div");
  row.className = role === "user" ? "flex justify-end" : "flex justify-start";

  const el = document.createElement("div");
  el.className = [
    "max-w-[85%] rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap",
    role === "user"
      ? "bg-sky-600 text-white rounded-br-sm"
      : "bg-slate-100 text-slate-800 rounded-bl-sm",
    pending ? "opacity-60" : "",
  ].join(" ");
  el.textContent = text;

  row.appendChild(el);
  log.appendChild(row);
  log.scrollTop = log.scrollHeight;
  return el;
}

async function health() {
  try {
    const res = await fetch(`${SAM_URL}/health`, { method: "GET" });
    return res.ok;
  } catch {
    return false;
  }
}

async function ask(message) {
  // Read the token fresh: Supabase rotates it, and a cached copy starts
  // failing an hour in.
  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session) {
    throw new Error("Your session expired. Sign in again.");
  }

  const res = await fetch(`${SAM_URL}/chat`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${data.session.access_token}`,
    },
    body: JSON.stringify({ message, history }),
  });

  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload.error || `SAM returned ${res.status}`);
  return payload.reply;
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const message = input.value.trim();
  if (!message) return;

  input.value = "";
  sendBtn.disabled = true;
  bubble("user", message);
  history.push({ role: "user", content: message });

  const thinking = bubble("assistant", "Thinking…", { pending: true });

  try {
    const reply = await ask(message);
    thinking.textContent = reply;
    thinking.classList.remove("opacity-60");
    history.push({ role: "assistant", content: reply });
  } catch (err) {
    thinking.textContent = err.message;
    thinking.className =
      "max-w-[85%] rounded-2xl rounded-bl-sm bg-rose-50 px-3.5 py-2 text-sm text-rose-700";
  } finally {
    sendBtn.disabled = false;
    input.focus();
  }
});

// SAM is a separate process, so "not running" is the likeliest failure.
(async () => {
  if (await health()) {
    status.textContent = "Connected";
    status.className = "text-xs text-emerald-600";
  } else {
    status.textContent = "SAM is not running";
    status.className = "text-xs text-slate-500";
    log.innerHTML = `<p class="text-sm text-slate-500">
      Start it with
      <code class="rounded bg-slate-100 px-1">python backend/sam/server.py</code>,
      then reload.</p>`;
    input.disabled = true;
    sendBtn.disabled = true;
  }
  panel.classList.remove("hidden");
})();
