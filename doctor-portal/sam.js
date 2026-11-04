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

// The model still reaches for markdown occasionally. Render the handful of
// constructs it uses rather than showing raw asterisks and pipes. Built from
// text nodes, never innerHTML — this is model output.
function render(el, text) {
  el.replaceChildren();

  for (const line of String(text).split("\n")) {
    const row = document.createElement("div");

    // A markdown table separator (|---|---|) carries no information once the
    // table is flattened.
    if (/^\s*\|[\s|:-]+\|\s*$/.test(line)) continue;

    let body = line;
    let bullet = false;
    if (/^\s*[-*]\s+/.test(line)) {
      body = line.replace(/^\s*[-*]\s+/, "");
      bullet = true;
    } else if (/^\s*\|/.test(line)) {
      // Flatten a table row into "a · b · c".
      body = line.replace(/^\s*\|/, "").replace(/\|\s*$/, "")
                 .split("|").map((c) => c.trim()).filter(Boolean).join(" · ");
    }

    if (bullet) {
      row.className = "flex gap-1.5";
      const dot = document.createElement("span");
      dot.textContent = "•";
      dot.className = "shrink-0";
      row.appendChild(dot);
    }

    const span = document.createElement("span");
    // **bold** and `code`; everything else stays literal text.
    for (const part of body.split(/(\*\*[^*]+\*\*|`[^`]+`)/g)) {
      if (!part) continue;
      if (part.startsWith("**") && part.endsWith("**")) {
        const b = document.createElement("strong");
        b.textContent = part.slice(2, -2);
        span.appendChild(b);
      } else if (part.startsWith("`") && part.endsWith("`")) {
        const c = document.createElement("code");
        c.className = "rounded bg-black/10 px-1 text-[0.95em]";
        c.textContent = part.slice(1, -1);
        span.appendChild(c);
      } else {
        span.appendChild(document.createTextNode(part));
      }
    }
    row.appendChild(span);
    el.appendChild(row);
  }
}

function bubble(role, text, { pending = false } = {}) {
  const row = document.createElement("div");
  row.className = role === "user" ? "flex justify-end" : "flex justify-start";

  const el = document.createElement("div");
  el.className = [
    "max-w-[85%] space-y-1 rounded-2xl px-3.5 py-2 text-sm leading-relaxed",
    role === "user"
      ? "bg-sky-600 text-white rounded-br-sm"
      : "bg-slate-100 text-slate-800 rounded-bl-sm",
    pending ? "opacity-60" : "",
  ].join(" ");
  render(el, text);

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
    render(thinking, reply);
    thinking.classList.remove("opacity-60");
    history.push({ role: "assistant", content: reply });
  } catch (err) {
    render(thinking, err.message);
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
