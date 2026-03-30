// login.js
import { supabase, redirectIfAuthed } from "./supabase.js";

const msgEl = document.getElementById("msg");
const loginForm = document.getElementById("loginForm");
const signupBtn = document.getElementById("signupBtn");

function showMsg(text) {
  msgEl.textContent = text;
  msgEl.classList.remove("hidden");
}

await redirectIfAuthed();

loginForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  msgEl.classList.add("hidden");

  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;

  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return showMsg(error.message);

  window.location.href = "app.html";
});

signupBtn.addEventListener("click", async () => {
  msgEl.classList.add("hidden");

  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;

  if (!email || !password) return showMsg("Enter email and password, then click Create one.");

  const { error } = await supabase.auth.signUp({ email, password });
  if (error) return showMsg(error.message);

  showMsg("Signup created. Check your email to confirm (if confirmation is enabled), then log in.");
  msgEl.classList.remove("text-red-600");
  msgEl.classList.add("text-green-700");
});
