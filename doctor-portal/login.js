import { supabase, redirectIfAuthed } from "./supabase.js";

const msgEl = document.getElementById("msg");
const authForm = document.getElementById("authForm");
const authTitle = document.getElementById("authTitle");
const authSubmitBtn = document.getElementById("authSubmitBtn");
const toggleModeBtn = document.getElementById("toggleModeBtn");
const fullNameInput = document.getElementById("fullName");

let mode = "signin";

function showMsg(text, isError = true) {
  msgEl.textContent = text;
  msgEl.className = `mt-4 rounded-lg px-3 py-2 text-sm ${
      isError ? "bg-red-50 text-red-700" : "bg-emerald-50 text-emerald-700"
  }`;
  msgEl.classList.remove("hidden");
}

function setMode(nextMode) {
  mode = nextMode;
  const isSignIn = mode === "signin";

  authTitle.textContent = isSignIn ? "Sign in" : "Create account";
  authSubmitBtn.textContent = isSignIn ? "Sign in" : "Create account";
  toggleModeBtn.textContent = isSignIn
      ? "Need an account? Create one"
      : "Already have an account? Sign in";

  if (fullNameInput) {
    fullNameInput.closest("div")?.classList.toggle("hidden", isSignIn);
    fullNameInput.value = "";
  }

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

  const emailInput = document.getElementById("email");
  const passwordInput = document.getElementById("password");

  const email = emailInput ? emailInput.value.trim() : "";
  const password = passwordInput ? passwordInput.value : "";

  if (!email || !password) {
    showMsg("Please enter your email and password.");
    return;
  }

  if (mode === "signin") {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      console.error("Sign in error:", error);
      showMsg(error.message, true);
      return;
    }

    window.location.href = "patients.html";
    return;
  }

  const fullName = fullNameInput ? fullNameInput.value.trim() : "";

  if (!fullName) {
    showMsg("Please enter your full name.");
    return;
  }

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

  if (error) {
    console.error("Sign up error:", error);
    showMsg(error.message, true);
    return;
  }

  if (data.user && !data.session) {
    showMsg(
        "Account created. Check your email and confirm your account before signing in.",
        false
    );
    return;
  }

  showMsg("Account created successfully.", false);
  window.location.href = "patients.html";
});