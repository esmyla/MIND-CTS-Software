import { createClient } from "@supabase/supabase-js";

const supabaseUrl = "https://gmvkqlrjyrlilxtpsfsy.supabase.co"
const supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdtdmtxbHJqeXJsaWx4dHBzZnN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk5NjAxNTQsImV4cCI6MjA3NTUzNjE1NH0.9O0IRESrig8sJIqNX_9W_gcIX8vOvTz-4i6gdPrGPSo"

export const supabase = createClient(supabaseUrl, supabaseAnonKey);