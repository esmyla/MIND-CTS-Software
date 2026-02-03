// supabase.js
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm";

export const SUPABASE_URL = "https://cmmumwwzydfebahhgfyi.supabase.co";
export const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNtbXVtd3d6eWRmZWJhaGhnZnlpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjI4MDkwNTAsImV4cCI6MjA3ODM4NTA1MH0.zJBi0owKoaycNzmtAm9_5ZsUwXIUmxAGuCy0AhsaoZc";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export async function requireAuthOrRedirect() {
  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session) {
    window.location.href = "index.html";
    return null;
  }
  return data.session;
}

export async function redirectIfAuthed() {
  const { data } = await supabase.auth.getSession();
  if (data.session) window.location.href = "app.html";
}