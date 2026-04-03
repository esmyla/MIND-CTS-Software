import { supabase, redirectIfAuthed } from "./supabase.js";

const msgEl = document.getElementById("msg");
const authForm = document.getElementById("authForm");
const authTitle = document.getElementById("authTitle");
const authSubmitBtn = document.getElementById("authSubmitBtn");
const toggleModeBtn = document.getElementById("toggleModeBtn");

let mode = "signin";

function showMsg(text, isError = true) {
  msgEl.textContent = text;
  msgEl.className = `mt-4 rounded-lg px-3 py-2 text-sm ${
    isError ? "bg-red-50 text-red-700" : "bg-emerald-50 text-emerald-700"
  }`;
}

function setMode(nextMode) {
  mode = nextMode;
  const isSignIn = mode === "signin";
  authTitle.textContent = isSignIn ? "Sign in" : "Create account";
  authSubmitBtn.textContent = isSignIn ? "Sign in" : "Create account";
  toggleModeBtn.textContent = isSignIn ? "Need an account? Create one" : "Already have an account? Sign in";
  msgEl.classList.add("hidden");
}

await redirectIfAuthed();

setMode("signin");

toggleModeBtn.addEventListener("click", () => {
  setMode(mode === "signin" ? "signup" : "signin");
});

authForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  msgEl.classList.add("hidden");

  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;

  if (mode === "signin") {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return showMsg(error.message, true);
    window.location.href = "patients.html";
    return;
  }

  const { error } = await supabase.auth.signUp({ email, password });
  if (error) return showMsg(error.message, true);

  showMsg(
    "Account created. If email confirmation is enabled in Supabase, verify your inbox before signing in.",
    false,
  );
});
