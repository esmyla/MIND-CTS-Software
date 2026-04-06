import { supabase, redirectIfAuthed } from "./supabase.js";

const msgEl = document.getElementById("msg");
const authForm = document.getElementById("authForm");
const authTitle = document.getElementById("authTitle");
const authSubmitBtn = document.getElementById("authSubmitBtn");
const toggleModeBtn = document.getElementById("toggleModeBtn");
const fullNameWrap = document.getElementById("fullNameWrap");
const roleHint = document.getElementById("roleHint");

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
  authTitle.textContent = isSignIn ? "Sign in" : "Create doctor account";
  authSubmitBtn.textContent = isSignIn ? "Sign in" : "Create account";
  toggleModeBtn.textContent = isSignIn ? "Need an account? Create one" : "Already have an account? Sign in";
  fullNameWrap.classList.toggle("hidden", isSignIn);
  roleHint.classList.toggle("hidden", isSignIn);
  msgEl.classList.add("hidden");
}

async function createProfile(user, fullName) {
  const payload = {
    user_id: user.id,
    full_name: fullName,
    email: user.email,
    role: "doctor",
  };

  const { error } = await supabase.from("profiles").upsert(payload, { onConflict: "user_id" });
  return error;
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
  const fullName = document.getElementById("fullName").value.trim();

  if (mode === "signin") {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) return showMsg(error.message, true);
    window.location.href = "patients.html";
    return;
  }

  if (!fullName) return showMsg("Please enter your full name.");

  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        full_name: fullName,
        role: "doctor",
      },
    },
  });

  if (error) return showMsg(error.message, true);

  if (data.user) {
    const profileError = await createProfile(data.user, fullName);
    if (profileError) {
      return showMsg(
        `Account created, but profile setup failed: ${profileError.message}. Run SQL setup script in webAppTest/sql/doctor_portal_setup.sql.`,
        true,
      );
    }
  }

  showMsg(
    "Doctor account created. If email confirmation is enabled in Supabase, verify your inbox before signing in.",
    false,
  );
});
