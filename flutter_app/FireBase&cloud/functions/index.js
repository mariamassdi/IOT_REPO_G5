/**
 * Firebase Cloud Functions (Gen2) — ROBUST OFFLINE SYNC
 */

const { onRequest } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// --- Helpers ---
function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function handleOptions(req, res) {
  if (req.method === "OPTIONS") {
    setCors(res);
    res.status(204).send("");
    return true;
  }
  return false;
}

function okJson(res, obj) {
  res.set("Content-Type", "application/json");
  return res.status(200).send(JSON.stringify(obj));
}

function dateKeyFromNowIsrael() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Jerusalem", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(new Date());
}

function tokenDocId(token) {
  return encodeURIComponent(String(token)).replace(/%/g, "_");
}

function numOrNull(x) {
  const n = Number(x);
  return Number.isFinite(n) ? n : null;
}

function safeDelta(curVal, prevVal) {
  if (curVal == null || prevVal == null) return null;
  const d = curVal - prevVal;
  return (Number.isFinite(d) && d > 0) ? d : null;
}

function toStringData(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj || {})) {
    if (v !== undefined) out[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  return out;
}

async function getTokensByRole(patientId, role) {
  const snap = await db.collection(`patients/${patientId}/deviceTokens`).where("role", "==", role).get();
  const tokens = [];
  const refs = [];
  snap.forEach((d) => {
    const data = d.data() || {};
    if (data.token) { tokens.push(String(data.token)); refs.push(d.ref); }
  });
  return { tokens, refs };
}

async function cleanupInvalidTokens(tokens, refs, resp) {
  const deletes = [];
  resp.responses.forEach((r, idx) => {
    if (!r.success) {
      const c = r.error && r.error.code ? String(r.error.code) : "";
      if (c.includes("registration-token-not-registered") || c.includes("invalid-registration-token")) {
        if (refs[idx]) deletes.push(refs[idx].delete());
      }
    }
  });
  if (deletes.length) await Promise.allSettled(deletes);
}

async function sendPushToRole(patientId, role, notification, data) {
  const { tokens, refs } = await getTokensByRole(patientId, role);
  if (!tokens.length) return { sent: 0 };
  const resp = await messaging.sendEachForMulticast({ tokens, notification, data: toStringData(data) });
  await cleanupInvalidTokens(tokens, refs, resp);
  return { sent: resp.successCount };
}

// --- HTTP Functions ---

exports.sessionState = onRequest({ region: "us-central1" }, async (req, res) => {
  if (handleOptions(req, res)) return;
  setCors(res);
  try {
    const patientId = (req.query.patientId || "p1").toString();
    const snap = await db.doc(`patients/${patientId}/tracking/currentSession`).get();
    if (!snap.exists) return okJson(res, { active: false, sessionId: "", dateKey: "" });
    const data = snap.data() || {};
    return okJson(res, { ...data, active: !!data.active });
  } catch (e) {
    console.error(e); return res.status(500).send("Error");
  }
});

exports.registerToken = onRequest({ region: "us-central1" }, async (req, res) => {
  if (handleOptions(req, res)) return;
  setCors(res);
  try {
    const { patientId, token, role, platform } = req.body;
    if (!token) return res.status(400).send("Missing token");
    await db.doc(`patients/${patientId}/deviceTokens/${tokenDocId(token)}`).set({
      token, role, platform: platform || null, updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    return okJson(res, { ok: true });
  } catch (e) {
    console.error(e); return res.status(500).send("Error");
  }
});

exports.startSession = onRequest({ region: "us-central1" }, async (req, res) => {
  if (handleOptions(req, res)) return;
  setCors(res);
  try {
    const patientId = (req.body.patientId || "p1").toString();
    const now = admin.firestore.FieldValue.serverTimestamp();
    const dateKey = dateKeyFromNowIsrael();
    
    const curRef = db.doc(`patients/${patientId}/tracking/currentSession`);
    const curSnap = await curRef.get();
    const cur = curSnap.exists ? (curSnap.data() || {}) : {};

    if (cur.active) return okJson(res, { active: true, sessionId: cur.sessionId, alreadyActive: true });

    const sessionRef = db.collection(`patients/${patientId}/sessions`).doc();
    const sessionId = sessionRef.id;

    await sessionRef.set({
      sessionId, patientId, dateKey, startTime: now, endTime: null,
      totalSteps: 0, stairsCount: 0, fallsCount: 0, alertsCount: 0, 
      activeWalkSeconds: 0, activeStairSeconds: 0, 
      lastUpdatedAt: now
    });

    await db.doc(`patients/${patientId}/daily/${dateKey}`).set({
      dateKey, lastUpdatedAt: now, sessionsCount: admin.firestore.FieldValue.increment(1)
    }, { merge: true });

    const startSteps = numOrNull(cur?.last?.steps) ?? 0;
    const startStairs = numOrNull(cur?.last?.stairsCount) ?? 0;
    const startFalls = numOrNull(cur?.last?.fallsCount) ?? 0;

    await curRef.set({
      active: true, sessionId, dateKey, startedAt: now, updatedAt: now,
      last: cur.last || null,
      sessionStart: { steps: startSteps, stairs: startStairs, falls: startFalls },
      live: { 
          steps: 0, stairsCount: 0, fallsCount: 0, imuMoving: false, source: "start",
          stepsPace: 0, stairsPace: 0
      },
      lastStepCount: startSteps, stairsCount: startStairs, fallsCount: startFalls,
      activeWalkSeconds: 0, activeStairSeconds: 0,
      okPending: false
    }, { merge: true });

    return okJson(res, { active: true, sessionId });
  } catch (e) {
    console.error(e); return res.status(500).send("Error");
  }
});

exports.stopSession = onRequest({ region: "us-central1" }, async (req, res) => {
  if (handleOptions(req, res)) return;
  setCors(res);
  try {
    const patientId = (req.body.patientId || "p1").toString();
    const now = admin.firestore.FieldValue.serverTimestamp();
    
    const curRef = db.doc(`patients/${patientId}/tracking/currentSession`);
    const curSnap = await curRef.get();
    const cur = curSnap.exists ? curSnap.data() || {} : {};
    
    await curRef.set({ active: false, okPending: false, updatedAt: now }, { merge: true });

    if (cur.sessionId) {
      const sessionDocRef = db.doc(`patients/${patientId}/sessions/${cur.sessionId}`);
      
      const live = cur.live || {};
      const finalSteps = live.steps || 0;
      const finalStairs = live.stairsCount || 0;
      const finalFalls = live.fallsCount || 0; 
      
      const walkSec = cur.activeWalkSeconds || 1;
      const stairSec = cur.activeStairSeconds || 1;
      
      const avgStepsPace = (finalSteps / (walkSec / 60));
      const avgStairsPace = (finalStairs / (stairSec / 60));

      await sessionDocRef.set({ 
          endTime: now, 
          lastUpdatedAt: now,
          totalSteps: finalSteps,
          stairsCount: finalStairs,
          fallsCount: finalFalls, 
          activeWalkSeconds: walkSec,
          activeStairSeconds: stairSec,
          avgStepsPace: Math.round(avgStepsPace),
          avgStairsPace: Math.round(avgStairsPace)
      }, { merge: true });
    }
    return okJson(res, { active: false });
  } catch (e) {
    console.error(e); return res.status(500).send("Error");
  }
});

exports.imOk = onRequest({ region: "us-central1" }, async (req, res) => {
  if (handleOptions(req, res)) return;
  setCors(res);
  try {
    const patientId = (req.body.patientId || "p1").toString();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.doc(`patients/${patientId}/tracking/currentSession`).set({ okPending: false, updatedAt: now }, { merge: true });
    await sendPushToRole(patientId, "caregiver", { title: "PATIENT OK", body: "The patient confirmed they are fine." }, { kind: "patient_ok" });
    const q = await db.collection(`patients/${patientId}/alerts`).where("handled", "==", false).get();
    if (!q.empty) {
        const docs = q.docs.map(d => ({ ref: d.ref, data: d.data() }));
        docs.sort((a, b) => { const tA = a.data.timestamp ? a.data.timestamp.toMillis() : 0; const tB = b.data.timestamp ? b.data.timestamp.toMillis() : 0; return tB - tA; });
        await docs[0].ref.set({ handled: true, handledAt: now, handledBy: "patient" }, { merge: true });
    }
    return okJson(res, { ok: true });
  } catch (e) {
    console.error(e); return res.status(500).send("Error");
  }
});

exports.caregiverHandleAlert = onRequest({ region: "us-central1" }, async (req, res) => {
  if (handleOptions(req, res)) return;
  setCors(res);
  if (req.method !== "POST") return res.status(405).send("POST only");
  try {
    const { patientId, alertId } = req.body;
    const now = admin.firestore.FieldValue.serverTimestamp();
    if (!patientId || !alertId) return res.status(400).send("Missing IDs");
    await db.doc(`patients/${patientId}/alerts/${alertId}`).set({ handled: true, handledAt: now, handledBy: "caregiver" }, { merge: true });
    await db.doc(`patients/${patientId}/tracking/currentSession`).set({ okPending: false, updatedAt: now }, { merge: true });
    return okJson(res, { success: true });
  } catch (e) {
    console.error(e); return res.status(500).send("Error");
  }
});

exports.receiveData = onRequest({ region: "us-central1" }, async (req, res) => {
  if (handleOptions(req, res)) return;
  setCors(res);
  try {
    const data = req.body || {};
    const patientId = (req.query.patientId || data.patientId || "p1").toString();
    const type = (data.type || "telemetry").toString();
    const now = admin.firestore.FieldValue.serverTimestamp();

    const curRef = db.doc(`patients/${patientId}/tracking/currentSession`);
    const curSnap = await curRef.get();
    const cur = curSnap.exists ? (curSnap.data() || {}) : {};

    if (cur.active && cur.startedAt) {
        const startTime = cur.startedAt.toDate();
        const currentTime = new Date();
        const diffMinutes = (currentTime - startTime) / 1000 / 60;

        if (diffMinutes >= 60) {
            console.log(`Auto-stopping session for ${patientId} after ${diffMinutes} minutes`);
            await curRef.set({ active: false, okPending: false, autoStopped: true }, { merge: true });
            
            if (cur.sessionId) {
                 await db.doc(`patients/${patientId}/sessions/${cur.sessionId}`).set({ 
                     endTime: now, 
                     autoStopped: true,
                     lastUpdatedAt: now
                 }, { merge: true });
            }
            cur.active = false;
        }
    }

    const newSteps = numOrNull(data.steps);
    const newStairs = numOrNull(data.stairsCount);
    const newFalls = numOrNull(data.fallsCount);

    let timeDiffSeconds = 0;
    if (cur.lastAt) {
        const lastTime = cur.lastAt.toDate();
        const currentTime = new Date();
        timeDiffSeconds = (currentTime - lastTime) / 1000;
        if (timeDiffSeconds > 60) timeDiffSeconds = 0;
        if (timeDiffSeconds < 0) timeDiffSeconds = 0;
    }

    const start = cur.sessionStart || { steps: 0, stairs: 0, falls: 0 };
    let baseSteps = start.steps; if (newSteps !== null && newSteps < baseSteps) baseSteps = newSteps; 
    let baseStairs = start.stairs; if (newStairs !== null && newStairs < baseStairs) baseStairs = newStairs;
    let baseFalls = start.falls; if (newFalls !== null && newFalls < baseFalls) baseFalls = newFalls;

    const prevLive = cur.live || {};
    const liveSteps = (newSteps !== null) ? (newSteps - baseSteps) : (prevLive.steps || 0);
    const liveStairs = (newStairs !== null) ? (newStairs - baseStairs) : (prevLive.stairsCount || 0);
    const liveFalls = (newFalls !== null) ? (newFalls - baseFalls) : (prevLive.fallsCount || 0);

    const prevStepsTotal = numOrNull(cur.lastStepCount) ?? baseSteps;
    const prevStairsTotal = numOrNull(cur.stairsCount) ?? baseStairs;
    const prevFallsTotal = numOrNull(cur.fallsCount) ?? baseFalls;

    const dSteps = safeDelta(newSteps, prevStepsTotal) || 0;
    const dStairs = safeDelta(newStairs, prevStairsTotal) || 0;
    const dFalls = safeDelta(newFalls, prevFallsTotal) || 0;

    let addWalkSec = 0;
    let addStairSec = 0;
    if (dStairs > 0) addStairSec = timeDiffSeconds;
    else if (dSteps > 0) addWalkSec = timeDiffSeconds;

    const currentWalkSec = (cur.activeWalkSeconds || 0) + addWalkSec;
    const currentStairSec = (cur.activeStairSeconds || 0) + addStairSec;

    const rawStepsPace = (currentWalkSec > 5) ? (liveSteps / (currentWalkSec / 60)) : 0;
    const rawStairsPace = (currentStairSec > 5) ? (liveStairs / (currentStairSec / 60)) : 0;

    const updatePayload = {
      updatedAt: now,
      lastAt: now,
      lastType: type,
      last: { ...cur.last, ...data, isFallActive: type === "fall_alert" },
      live: { 
        steps: liveSteps,
        stairsCount: liveStairs,
        fallsCount: liveFalls,
        imuMoving: (data.imuMoving !== undefined) ? data.imuMoving : (prevLive.imuMoving || false),
        source: data.source || prevLive.source || "unknown",
        stepsPace: Math.round(rawStepsPace),
        stairsPace: Math.round(rawStairsPace)
      },
      lastStepCount: newSteps !== null ? newSteps : cur.lastStepCount,
      stairsCount: newStairs !== null ? newStairs : cur.stairsCount,
      fallsCount: newFalls !== null ? newFalls : cur.fallsCount,
      activeWalkSeconds: currentWalkSec,
      activeStairSeconds: currentStairSec
    };
    
    if ((newSteps !== null && newSteps < start.steps) || 
        (newStairs !== null && newStairs < start.stairs) ||
        (newFalls !== null && newFalls < start.falls)) {
        updatePayload.sessionStart = { steps: baseSteps, stairs: baseStairs, falls: baseFalls };
    }

    await curRef.set(updatePayload, { merge: true });

    const statsUpdate = {};
    if (dSteps > 0) statsUpdate.totalSteps = admin.firestore.FieldValue.increment(dSteps);
    if (dStairs > 0) statsUpdate.stairsCount = admin.firestore.FieldValue.increment(dStairs);
    if (dFalls > 0) statsUpdate.fallsCount = admin.firestore.FieldValue.increment(dFalls);
    
    if (dFalls > 0 || type === "fall_alert" || type === "long_immobility") {
        statsUpdate.alertsCount = admin.firestore.FieldValue.increment(dFalls > 0 ? dFalls : 1);
    }

    if (addWalkSec > 0) statsUpdate.activeWalkSeconds = admin.firestore.FieldValue.increment(addWalkSec);
    if (addStairSec > 0) statsUpdate.activeStairSeconds = admin.firestore.FieldValue.increment(addStairSec);

    if (Object.keys(statsUpdate).length > 0) {
       await db.doc(`patients/${patientId}/daily/${cur.dateKey}`).set(statsUpdate, { merge: true });
       if (cur.sessionId) {
          await db.doc(`patients/${patientId}/sessions/${cur.sessionId}`).set(statsUpdate, { merge: true });
       }
    }
    
    if (type === "fall_alert" || type === "long_immobility" || (dFalls > 0 && type === "telemetry")) {
       const alertType = (type === "telemetry" && dFalls > 0) ? "fall_alert" : type;
       
       await db.collection(`patients/${patientId}/alerts`).add({
         type: alertType, 
         patientId, 
         sessionId: cur.sessionId, 
         timestamp: now, 
         handled: false, 
         payload: { ...data, note: type === "telemetry" ? "Synced from offline" : "Realtime" }
       });
       if (cur.active) {
          await curRef.set({ okPending: true }, { merge: true });
       }
    }

    return res.status(200).send("Saved");
  } catch (err) {
    console.error(err);
    return res.status(500).send("Server error");
  }
});

exports.onAlertCreated = onDocumentCreated(
  { region: "us-central1", document: "patients/{patientId}/alerts/{alertId}" },
  async (event) => {
    try {
      const snap = event.data;
      if (!snap) return;
      const patientId = event.params.patientId;
      const type = (snap.data().type || "alert").toString();
      await sendPushToRole(patientId, "caregiver", { title: "ALERT", body: type }, { kind: "alert" });
    } catch (e) { console.error(e); }
  }
);