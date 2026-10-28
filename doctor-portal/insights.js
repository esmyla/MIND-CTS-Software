// Turning measurements into statements.
//
// Every number this product collects is a raw ADC reading or an angle. On its
// own none of it answers the question a clinician actually has — is this
// patient getting better? This module does that conversion in one place so the
// dashboard and the patient app cannot drift into saying different things
// about the same data.

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/** Significant-figure-honest force reading.
 *
 * The FSR is a 12-bit ADC with no calibration to newtons or kilograms, so
 * `1400.00` claims a precision that does not exist. Round to whole units and
 * label them as sensor units, never as force.
 */
export function formatForce(value) {
  if (value === null || value === undefined || Number.isNaN(value)) return "—";
  return Math.round(value).toLocaleString();
}

export function formatAngle(value) {
  if (value === null || value === undefined || Number.isNaN(value)) return "—";
  return `${Math.round(value)}°`;
}

/** A ratio (1.4) as a signed percentage change ("+40%"). */
export function formatChange(ratio) {
  if (ratio === null || ratio === undefined || Number.isNaN(ratio)) return null;
  const pct = (ratio - 1) * 100;
  const sign = pct >= 0 ? "+" : "";
  // Below a tenth of a percent, "+0.0%" reads as a measurement rather than as
  // "no meaningful change".
  if (Math.abs(pct) < 0.1) return "no change";
  return `${sign}${pct.toFixed(0)}%`;
}

/** A ratio as a percentage of baseline ("140% of baseline"). */
export function formatOfBaseline(ratio) {
  if (ratio === null || ratio === undefined || Number.isNaN(ratio)) return null;
  return `${Math.round(ratio * 100)}% of baseline`;
}

export function formatDate(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString();
}

// ---------------------------------------------------------------------------
// Trend
// ---------------------------------------------------------------------------

/** Least-squares slope of y over its index. Null if fewer than two points. */
function slope(values) {
  const ys = values.filter((v) => typeof v === "number" && !Number.isNaN(v));
  if (ys.length < 2) return null;
  const n = ys.length;
  const meanX = (n - 1) / 2;
  const meanY = ys.reduce((a, b) => a + b, 0) / n;
  let num = 0;
  let den = 0;
  for (let i = 0; i < n; i++) {
    num += (i - meanX) * (ys[i] - meanY);
    den += (i - meanX) ** 2;
  }
  return den === 0 ? null : num / den;
}

/** A plain-language verdict on a series.
 *
 * Returns { label, tone, detail }. `tone` is one of "good" | "flat" | "bad" |
 * "unknown" so callers can colour it without re-deciding what it means.
 *
 * Refuses to judge fewer than three sessions. Two points always have a slope,
 * and calling that a trend would turn ordinary session-to-session variation —
 * a differently seated glove, a worse night's sleep — into a clinical finding.
 */
export function trendVerdict(values, { minSessions = 3 } = {}) {
  const ys = values.filter((v) => typeof v === "number" && !Number.isNaN(v));

  if (ys.length === 0) {
    return { label: "No data", tone: "unknown", detail: "No sessions recorded yet." };
  }
  if (ys.length < minSessions) {
    const need = minSessions - ys.length;
    return {
      label: "Too early to say",
      tone: "unknown",
      detail: `${ys.length} session${ys.length === 1 ? "" : "s"} so far. ` +
              `${need} more before a trend means anything.`,
    };
  }

  const m = slope(ys);
  if (m === null) return { label: "Too early to say", tone: "unknown", detail: "" };

  // Express the slope as percent-of-starting-value per session, so the
  // threshold means the same thing for a grip reading of 300 and one of 3000.
  const base = Math.abs(ys[0]) || 1;
  const perSession = (m / base) * 100;

  // 1% per session is roughly 10% over a ten-session course of therapy: small
  // enough to catch real progress, large enough to ignore noise.
  if (perSession > 1) {
    return {
      label: "Improving",
      tone: "good",
      detail: `About ${perSession.toFixed(1)}% per session across ${ys.length} sessions.`,
    };
  }
  if (perSession < -1) {
    return {
      label: "Declining",
      tone: "bad",
      detail: `Down about ${Math.abs(perSession).toFixed(1)}% per session across ${ys.length} sessions.`,
    };
  }
  return {
    label: "Plateaued",
    tone: "flat",
    detail: `Within ±1% per session across ${ys.length} sessions.`,
  };
}

// ---------------------------------------------------------------------------
// Adherence
// ---------------------------------------------------------------------------

/** Adherence over the last [days] days from pt_sessions rows.
 *
 * Counts DAYS the patient did something, not total exercises: six exercises in
 * one burst and nothing all week is not better adherence than one exercise a
 * day for six days, and a raw count would say it was.
 */
export function adherence(rows, days = 30) {
  const byDay = new Set();
  for (const r of rows || []) {
    if (r.completed_on) byDay.add(r.completed_on);
  }

  const today = new Date();
  const strip = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setDate(d.getDate() - i);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
    strip.push({ date: key, active: byDay.has(key) });
  }

  const activeDays = strip.filter((d) => d.active).length;
  return {
    strip,
    activeDays,
    totalDays: days,
    percent: Math.round((activeDays / days) * 100),
  };
}

// ---------------------------------------------------------------------------
// Exertion
// ---------------------------------------------------------------------------

/** Strength per unit of exertion, as a percentage.
 *
 * 100% means the patient produced their baseline force at their baseline heart
 * rate. Above 100% is more force for proportionally less cardiovascular cost.
 *
 * Null unless both the strength ratio and a resting heart rate are known — a
 * half-computed score gets read as a real one.
 */
export function exertionScore(row, restingBpm) {
  if (!row || !restingBpm || restingBpm <= 0) return null;
  const strength = row.r_fsr_palm;
  const bpm = row.bpm_avg;
  if (!strength || strength <= 0 || !bpm || bpm <= 0) return null;
  return (strength / (bpm / restingBpm)) * 100;
}

// ---------------------------------------------------------------------------
// CSV
// ---------------------------------------------------------------------------

/** RFC-4180-ish CSV. Quotes every field so commas and newlines in notes or
 *  device names cannot shift a column.
 */
export function toCsv(headers, rows) {
  const esc = (v) => {
    const s = v === null || v === undefined ? "" : String(v);
    return `"${s.replace(/"/g, '""')}"`;
  };
  return [
    headers.map(esc).join(","),
    ...rows.map((r) => r.map(esc).join(",")),
  ].join("\r\n");
}

export function downloadCsv(filename, csv) {
  // BOM so Excel opens UTF-8 correctly instead of mangling any non-ASCII.
  const blob = new Blob([`﻿${csv}`], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
