// app.js
import { supabase, requireAuthOrRedirect } from "./supabase.js";

const menuBtn = document.getElementById("menuBtn");
const menu = document.getElementById("menu");
const logoutBtn = document.getElementById("logoutBtn");

await requireAuthOrRedirect();

menuBtn.addEventListener("click", () => {
  menu.classList.toggle("hidden");
});

// click outside to close
document.addEventListener("click", (e) => {
  if (menu.classList.contains("hidden")) return;
  const clickedInside = menu.contains(e.target) || menuBtn.contains(e.target);
  if (!clickedInside) menu.classList.add("hidden");
});

logoutBtn.addEventListener("click", async () => {
  await supabase.auth.signOut();
  window.location.href = "index.html";
});