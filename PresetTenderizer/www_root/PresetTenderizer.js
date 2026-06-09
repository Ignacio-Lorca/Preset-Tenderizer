var WEB_SECTION = "PresetTenderizerWeb";
var pendingCommandResolve = null;
var pendingCommandReject = null;
var pendingCommandId = null;
var commandTimeoutId = null;
var commandPollId = null;

var COPY = {
  serve: "Serve",
  connecting: "Warming the blender…",
  connected: "Blender running",
  stale: "Blender stalled — run WebBridge",
  emptyDetails: "Pick something from the menu or tenderize a new preset",
  toastPickPresetToLoad: "Pick a preset from the menu first",
  toastPickPresetToInspect: "Pick a preset from the menu first",
  toastEnterPresetName: "Name this tender cut",
  toastPickPresetToUpdate: "Pick a preset from the menu first",
  toastPickPresetToDelete: "Pick a preset from the menu first",
  toastPickPresetToRename: "Pick a preset from the menu first",
  toastEnterMusicianName: "Enter a band member name",
  metaFxCuts: "FX cuts",
  metaMonitorPours: "monitor pours",
  detailsTenderized: "Tenderized",
  detailsFxCuts: "FX cuts",
  detailsMonitorPours: "Monitor pours",
  tooltips: {
    roster: "Open band roster: add, rename, or remove members and their preset collections",
    tenderize: "Save current vocal/instrument FX and monitor routing as a new preset",
    retenderize: "Overwrite the selected preset with the current REAPER state",
    serve: "Load this preset into the project (FX chains, track names, monitor receives)",
    serveRow: "Load this preset into REAPER",
    tossBatch: "Delete the selected preset permanently",
    relabel: "Rename the selected preset",
    peekInside: "View raw JSON for the selected preset (debug)",
    addMusician: "Add a new band member with their own presets and track layout",
    musicianRename: "Rename this band member",
    musicianDelete: "Delete this band member and all their presets",
    modalClose: "Close",
    jsonReload: "Reload snapshot JSON from REAPER",
    jsonCopy: "Copy snapshot JSON to the clipboard",
  },
};

var state = {
  data: null,
  selectedName: "",
  loadingSnapshot: false,
};

var SESSION_USER_KEY = "pt_session_user_id";

var els = {};

function userExists(userId) {
  var users = (state.data && state.data.users) || [];
  var i;

  for (i = 0; i < users.length; i++) {
    if (users[i].id === userId) {
      return true;
    }
  }
  return false;
}

function setSessionUserId(userId) {
  if (userId) {
    sessionStorage.setItem(SESSION_USER_KEY, userId);
  }
}

function getSessionUserId() {
  if (!state.data) {
    return sessionStorage.getItem(SESSION_USER_KEY) || "";
  }

  var stored = sessionStorage.getItem(SESSION_USER_KEY);
  if (stored && userExists(stored)) {
    return stored;
  }

  var fallback = state.data.active_user_id || "";
  if (!fallback || !userExists(fallback)) {
    var users = state.data.users || [];
    fallback = users[0] ? users[0].id : "";
  }

  if (fallback) {
    sessionStorage.setItem(SESSION_USER_KEY, fallback);
  }
  return fallback;
}

function sessionUserSlice() {
  var id = getSessionUserId();
  if (!id || !state.data || !state.data.per_user) {
    return null;
  }
  return state.data.per_user[id] || null;
}

function parseProjExtJson(raw) {
  if (!raw) {
    return null;
  }

  var candidates = [raw];
  if (typeof simple_unescape === "function") {
    candidates.push(simple_unescape(raw));
  }

  var i, err;
  for (i = 0; i < candidates.length; i++) {
    try {
      return JSON.parse(candidates[i]);
    } catch (e) {
      err = e;
    }
  }

  throw err || new Error("Invalid JSON from REAPER bridge.");
}

function initElements() {
  els.connectionStatus = document.getElementById("connectionStatus");
  els.musicianSelect = document.getElementById("musicianSelect");
  els.manageMusiciansBtn = document.getElementById("manageMusiciansBtn");
  els.musiciansModal = document.getElementById("musiciansModal");
  els.musiciansModalClose = document.getElementById("musiciansModalClose");
  els.newMusicianName = document.getElementById("newMusicianName");
  els.addMusicianBtn = document.getElementById("addMusicianBtn");
  els.musiciansList = document.getElementById("musiciansList");
  els.vocalTrack = document.getElementById("vocalTrack");
  els.instrumentTrack = document.getElementById("instrumentTrack");
  els.monitorTrack = document.getElementById("monitorTrack");
  els.projectMeta = document.getElementById("projectMeta");
  els.filterInput = document.getElementById("filterInput");
  els.snapshotList = document.getElementById("snapshotList");
  els.snapshotName = document.getElementById("snapshotName");
  els.snapshotDetails = document.getElementById("snapshotDetails");
  els.captureBtn = document.getElementById("captureBtn");
  els.updateBtn = document.getElementById("updateBtn");
  els.loadBtn = document.getElementById("loadBtn");
  els.deleteBtn = document.getElementById("deleteBtn");
  els.renameBtn = document.getElementById("renameBtn");
  els.debugJsonBtn = document.getElementById("debugJsonBtn");
  els.message = document.getElementById("message");
  els.jsonModal = document.getElementById("jsonModal");
  els.jsonModalTitle = document.getElementById("jsonModalTitle");
  els.jsonModalNote = document.getElementById("jsonModalNote");
  els.jsonModalContent = document.getElementById("jsonModalContent");
  els.jsonModalFullFx = document.getElementById("jsonModalFullFx");
  els.jsonModalReload = document.getElementById("jsonModalReload");
  els.jsonModalCopy = document.getElementById("jsonModalCopy");
  els.jsonModalClose = document.getElementById("jsonModalClose");
  els.vocalFxNames = document.getElementById("vocalFxNames");
  els.instrumentFxNames = document.getElementById("instrumentFxNames");
  els.sectionMusician = document.getElementById("sectionMusician");
  els.sectionTrackSetup = document.getElementById("sectionTrackSetup");
  els.sectionSnapshots = document.getElementById("sectionSnapshots");
  els.sectionDetails = document.getElementById("sectionDetails");
}

function applyStaticTooltips() {
  var map = [
    ["manageMusiciansBtn", "roster"],
    ["captureBtn", "tenderize"],
    ["updateBtn", "retenderize"],
    ["loadBtn", "serve"],
    ["deleteBtn", "tossBatch"],
    ["renameBtn", "relabel"],
    ["debugJsonBtn", "peekInside"],
    ["addMusicianBtn", "addMusician"],
    ["musiciansModalClose", "modalClose"],
    ["jsonModalClose", "modalClose"],
    ["jsonModalReload", "jsonReload"],
    ["jsonModalCopy", "jsonCopy"],
  ];
  var i, el;

  for (i = 0; i < map.length; i++) {
    el = document.getElementById(map[i][0]);
    if (el) {
      el.title = COPY.tooltips[map[i][1]];
    }
  }
}

function wwr_onreply(results) {
  var lines = results.split("\n");
  var i, tok, payload, age, response;

  for (i = 0; i < lines.length; i++) {
    tok = lines[i].split("\t");
    if (tok.length < 4) {
      continue;
    }

    if (tok[0] === "PROJEXTSTATE" && tok[1] === WEB_SECTION && tok[2] === "state") {
      try {
        payload = parseProjExtJson(tok[3]);
        if (!payload) {
          continue;
        }
        state.data = payload;
        age = Math.floor(Date.now() / 1000) - (payload.updated_at || 0);
        setConnection(age < 4, age < 4 ? COPY.connected : COPY.stale);
        render();
      } catch (e) {}
    }

    if (tok[0] === "PROJEXTSTATE" && tok[1] === WEB_SECTION && tok[2] === "response") {
      if (!pendingCommandResolve && !pendingCommandReject) {
        continue;
      }
      try {
        response = parseProjExtJson(tok[3]);
        if (!response || response.id !== pendingCommandId) {
          continue;
        }
      } catch (e) {
        clearInterval(commandPollId);
        clearTimeout(commandTimeoutId);
        if (pendingCommandReject) {
          pendingCommandReject(e);
        }
        pendingCommandResolve = null;
        pendingCommandReject = null;
        pendingCommandId = null;
        continue;
      }

      clearInterval(commandPollId);
      clearTimeout(commandTimeoutId);
      if (response.ok && pendingCommandResolve) {
        pendingCommandResolve(response);
      } else if (!response.ok && pendingCommandReject) {
        pendingCommandReject(new Error(response.message || "Command failed"));
      }
      pendingCommandResolve = null;
      pendingCommandReject = null;
      pendingCommandId = null;
    }
  }
}

function requestState() {
  wwr_req("GET/PROJEXTSTATE/" + WEB_SECTION + "/state");
}

function sendCommand(body) {
  return new Promise(function (resolve, reject) {
    var cmd = { id: Date.now() };
    var key;
    var payload = body || {};

    if (!payload.user_id && state.data) {
      payload.user_id = getSessionUserId();
    }

    for (key in payload) {
      if (Object.prototype.hasOwnProperty.call(payload, key)) {
        cmd[key] = payload[key];
      }
    }

    pendingCommandResolve = resolve;
    pendingCommandReject = reject;
    pendingCommandId = cmd.id;

    wwr_req("SET/PROJEXTSTATE/" + WEB_SECTION + "/command/" + encodeURIComponent(JSON.stringify(cmd)));

    clearInterval(commandPollId);
    commandPollId = setInterval(function () {
      wwr_req("GET/PROJEXTSTATE/" + WEB_SECTION + "/response");
    }, 150);

    commandTimeoutId = setTimeout(function () {
      if (pendingCommandResolve || pendingCommandReject) {
        clearInterval(commandPollId);
        reject(new Error("Bridge timed out. Run PresetTenderizer_WebBridge.lua in REAPER."));
        pendingCommandResolve = null;
        pendingCommandReject = null;
        pendingCommandId = null;
      }
    }, 15000);
  });
}

function showMessage(text, ok) {
  els.message.hidden = false;
  els.message.textContent = text;
  els.message.className = "message " + (ok ? "ok" : "error");
}

function clearMessage() {
  els.message.hidden = true;
}

function setConnection(connected, label) {
  els.connectionStatus.className = "status " + (connected ? "connected" : "disconnected");
  els.connectionStatus.querySelector(".label").textContent = label;
}

function trackOptions(tracks, selectedGuid) {
  var options = ['<option value="">(not set)</option>'];
  var i, track, label, selected;

  for (i = 0; i < (tracks || []).length; i++) {
    track = tracks[i];
    label = track.index + ": " + (track.name || "(unnamed)");
    selected = track.guid === selectedGuid ? " selected" : "";
    options.push('<option value="' + escapeHtml(track.guid) + '"' + selected + ">" + escapeHtml(label) + "</option>");
  }
  return options.join("");
}

function ensureTrackInList(tracks, savedGuid, allTracks) {
  var list = (tracks || []).slice();
  var i, track, found;

  if (!savedGuid) {
    return list;
  }

  for (i = 0; i < list.length; i++) {
    if (list[i].guid === savedGuid) {
      return list;
    }
  }

  for (i = 0; i < (allTracks || []).length; i++) {
    track = allTracks[i];
    if (track.guid === savedGuid) {
      list.push(track);
      return list;
    }
  }

  return list;
}

function formatDate(epoch) {
  if (!epoch) {
    return "—";
  }
  return new Date(epoch * 1000).toLocaleString();
}

function filteredSnapshots() {
  var filter = els.filterInput.value.trim().toLowerCase();
  var slice = sessionUserSlice();
  var snapshots = (slice && slice.snapshots) || [];
  var out = [];
  var i;

  if (!filter) {
    return snapshots;
  }

  for (i = 0; i < snapshots.length; i++) {
    if (snapshots[i].name.toLowerCase().indexOf(filter) !== -1) {
      out.push(snapshots[i]);
    }
  }
  return out;
}

function formatSnapshotMetaLine(snap) {
  return (
    (snap.track_count || 0) +
    " " +
    COPY.metaFxCuts +
    " · " +
    (snap.receive_count || 0) +
    " " +
    COPY.metaMonitorPours
  );
}

function selectSnapshot(name) {
  state.selectedName = name;
  els.snapshotName.value = name;
  renderSnapshots();
  renderDetails();
}

function updateLoadButtonsDisabled() {
  var disabled = state.loadingSnapshot;
  var buttons = els.snapshotList
    ? els.snapshotList.querySelectorAll(".snapshot-load-btn")
    : [];
  var i;

  if (els.loadBtn) {
    els.loadBtn.disabled = disabled;
  }

  for (i = 0; i < buttons.length; i++) {
    buttons[i].disabled = disabled;
  }
}

function loadSnapshot(name) {
  if (!name) {
    showMessage(COPY.toastPickPresetToLoad, false);
    return Promise.resolve();
  }

  if (state.loadingSnapshot) {
    return Promise.resolve();
  }

  state.loadingSnapshot = true;
  updateLoadButtonsDisabled();
  clearMessage();

  return sendCommand({ action: "load", name: name })
    .then(function (response) {
      state.selectedName = name;
      els.snapshotName.value = name;
      showMessage(response.message, true);
      requestState();
    })
    .catch(function (err) {
      showMessage(err.message, false);
    })
    .then(function () {
      state.loadingSnapshot = false;
      updateLoadButtonsDisabled();
    });
}

function renderSnapshots() {
  var items = filteredSnapshots();
  var html = "";
  var i, snap, selected;

  if (!state.selectedName && items[0]) {
    state.selectedName = items[0].name;
    els.snapshotName.value = items[0].name;
  }

  for (i = 0; i < items.length; i++) {
    snap = items[i];
    selected = snap.name === state.selectedName ? "selected" : "";
    html +=
      '<li class="' +
      selected +
      '" data-name="' +
      escapeHtml(snap.name) +
      '">' +
      '<div class="snapshot-item-main">' +
      '<div class="name">' +
      escapeHtml(snap.name) +
      "</div>" +
      '<div class="meta-line">' +
      escapeHtml(formatSnapshotMetaLine(snap)) +
      "</div></div>" +
      '<button type="button" class="primary snapshot-load-btn"' +
      (state.loadingSnapshot ? " disabled" : "") +
      ' title="' +
      escapeHtml(COPY.tooltips.serveRow) +
      '" aria-label="' +
      escapeHtml(COPY.serve + " preset " + snap.name) +
      '">' +
      escapeHtml(COPY.serve) +
      "</button></li>";
  }

  els.snapshotList.innerHTML = html;

  var nodes = els.snapshotList.querySelectorAll("li");
  for (i = 0; i < nodes.length; i++) {
    (function (li) {
      var main = li.querySelector(".snapshot-item-main");
      var loadBtn = li.querySelector(".snapshot-load-btn");
      var snapshotName = li.getAttribute("data-name");

      if (main) {
        main.onclick = function () {
          selectSnapshot(snapshotName);
        };
      }

      if (loadBtn) {
        loadBtn.onclick = function (event) {
          event.stopPropagation();
          selectSnapshot(snapshotName);
          loadSnapshot(snapshotName);
        };
      }
    })(nodes[i]);
  }

  updateLoadButtonsDisabled();
  renderDetails();
}

function renderDetails() {
  var slice = sessionUserSlice();
  var snapshots = (slice && slice.snapshots) || [];
  var snap = null;
  var i;

  for (i = 0; i < snapshots.length; i++) {
    if (snapshots[i].name === state.selectedName) {
      snap = snapshots[i];
      break;
    }
  }

  if (!snap) {
    els.snapshotDetails.textContent = COPY.emptyDetails;
    return;
  }

  els.snapshotDetails.innerHTML =
    "<div><strong>Vocal:</strong> " +
    escapeHtml(snap.vocal_track_name || "—") +
    "</div>" +
    "<div><strong>Instrument:</strong> " +
    escapeHtml(snap.instrument_track_name || "—") +
    "</div>" +
    "<div><strong>Monitor:</strong> " +
    escapeHtml(snap.monitor_track_name || "—") +
    "</div>" +
    "<div><strong>" +
    COPY.detailsTenderized +
    ":</strong> " +
    formatDate(snap.created) +
    "</div>" +
    "<div><strong>" +
    COPY.detailsFxCuts +
    ":</strong> " +
    (snap.vocal_fx_count || 0) +
    " vocal, " +
    (snap.instrument_fx_count || 0) +
    " instrument</div>" +
    "<div><strong>" +
    COPY.detailsMonitorPours +
    ":</strong> " +
    (snap.receive_count || 0) +
    "</div>";
}

function renderTrackSelect(selectEl, tracks, savedGuid, allTracks) {
  var preserved = selectEl.value;
  var guid = savedGuid || "";
  var displayTracks = ensureTrackInList(tracks, savedGuid, allTracks);
  var i;

  if (preserved) {
    for (i = 0; i < displayTracks.length; i++) {
      if (displayTracks[i].guid === preserved) {
        guid = preserved;
        break;
      }
    }
  }

  selectEl.innerHTML = trackOptions(displayTracks, guid);
  selectEl.value = guid;
}

function saveTrackConfig() {
  return sendCommand({
    action: "set_config",
    vocal_guid: els.vocalTrack.value,
    instrument_guid: els.instrumentTrack.value,
    monitor_guid: els.monitorTrack.value,
  });
}

function renderMusicianSelect() {
  var users = (state.data && state.data.users) || [];
  var sessionId = getSessionUserId();
  var html = "";
  var i, user, selected;

  for (i = 0; i < users.length; i++) {
    user = users[i];
    selected = user.id === sessionId ? " selected" : "";
    html +=
      '<option value="' +
      escapeHtml(user.id) +
      '"' +
      selected +
      ">" +
      escapeHtml(user.display_name || user.id) +
      "</option>";
  }

  els.musicianSelect.innerHTML = html;
  els.musicianSelect.value = sessionId;
}

function renderMusiciansModal() {
  var users = (state.data && state.data.users) || [];
  var html = "";
  var i, user;

  for (i = 0; i < users.length; i++) {
    user = users[i];
    html +=
      '<li data-user-id="' +
      escapeHtml(user.id) +
      '">' +
      '<div class="musician-item-meta">' +
      '<div class="musician-item-name">' +
      escapeHtml(user.display_name || user.id) +
      "</div>" +
      '<div class="musician-item-sub">' +
      (user.snapshot_count || 0) +
      " snapshots</div>" +
      "</div>" +
      '<div class="musician-item-actions">' +
      '<button class="secondary musician-rename" type="button" title="' +
      escapeHtml(COPY.tooltips.musicianRename) +
      '">Rename</button>' +
      '<button class="danger musician-delete" type="button" title="' +
      escapeHtml(COPY.tooltips.musicianDelete) +
      '">Delete</button>' +
      "</div></li>";
  }

  els.musiciansList.innerHTML = html;

  var items = els.musiciansList.querySelectorAll("li");
  for (i = 0; i < items.length; i++) {
    (function (item) {
      var userId = item.getAttribute("data-user-id");
      item.querySelector(".musician-rename").onclick = function () {
        var currentName = item.querySelector(".musician-item-name").textContent;
        var newName = prompt("Rename musician:", currentName);
        if (!newName || newName === currentName) {
          return;
        }
        clearMessage();
        sendCommand({ action: "rename_user", user_id: userId, display_name: newName })
          .then(function (response) {
            showMessage(response.message, true);
            requestState();
          })
          .catch(function (err) {
            showMessage(err.message, false);
          });
      };
      item.querySelector(".musician-delete").onclick = function () {
        if (!confirm('Delete musician "' + item.querySelector(".musician-item-name").textContent + '" and all snapshots?')) {
          return;
        }
        clearMessage();
        sendCommand({ action: "delete_user", user_id: userId })
          .then(function (response) {
            var users = (state.data && state.data.users) || [];
            var i, remaining = [];

            if (getSessionUserId() === userId) {
              for (i = 0; i < users.length; i++) {
                if (users[i].id !== userId) {
                  remaining.push(users[i].id);
                }
              }
              if (remaining.length > 0) {
                setSessionUserId(remaining[0]);
              }
            }

            state.selectedName = "";
            els.snapshotName.value = "";
            showMessage(response.message, true);
            requestState();
          })
          .catch(function (err) {
            showMessage(err.message, false);
          });
      };
    })(items[i]);
  }
}

function openMusiciansModal() {
  renderMusiciansModal();
  els.musiciansModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeMusiciansModal() {
  els.musiciansModal.hidden = true;
  document.body.style.overflow = "";
}

function switchMusician(userId) {
  if (!userId || getSessionUserId() === userId) {
    return;
  }

  setSessionUserId(userId);
  clearMessage();
  state.selectedName = "";
  els.snapshotName.value = "";
  render();
}

function renderFxStatusChips(tracks) {
  var html = "";
  var i, track, chipClass;

  if (!tracks || tracks.length === 0) {
    return "—";
  }

  for (i = 0; i < tracks.length; i++) {
    track = tracks[i];
    if (i > 0) {
      html += '<span class="fx-status-sep">·</span>';
    }
    chipClass = track.muted ? "fx-status-chip" : "fx-status-chip active";
    html += '<span class="' + chipClass + '">' + escapeHtml(track.name || "(unnamed)") + "</span>";
  }

  return html;
}

function renderLiveFx() {
  var slice = sessionUserSlice();
  var liveFx = (slice && slice.live_fx) || {};

  if (els.vocalFxNames) {
    els.vocalFxNames.innerHTML = renderFxStatusChips(liveFx.vocal);
  }
  if (els.instrumentFxNames) {
    els.instrumentFxNames.innerHTML = renderFxStatusChips(liveFx.instrument);
  }
}

var SECTION_STORAGE_PREFIX = "pt_section_";

function restoreSectionState() {
  var sections = [
    { el: els.sectionMusician, id: "musician" },
    { el: els.sectionTrackSetup, id: "trackSetup" },
    { el: els.sectionSnapshots, id: "snapshots" },
    { el: els.sectionDetails, id: "details" },
  ];
  var i, item, stored;

  for (i = 0; i < sections.length; i++) {
    item = sections[i];
    if (!item.el) {
      continue;
    }
    stored = localStorage.getItem(SECTION_STORAGE_PREFIX + item.id);
    if (stored === "closed") {
      item.el.open = false;
    } else if (stored === "open") {
      item.el.open = true;
    }
  }
}

function bindSectionPersistence() {
  var sections = [
    { el: els.sectionMusician, id: "musician" },
    { el: els.sectionTrackSetup, id: "trackSetup" },
    { el: els.sectionSnapshots, id: "snapshots" },
    { el: els.sectionDetails, id: "details" },
  ];
  var i, item;

  for (i = 0; i < sections.length; i++) {
    item = sections[i];
    if (!item.el) {
      continue;
    }
    item.el.addEventListener("toggle", function (sectionId, detailsEl) {
      return function () {
        localStorage.setItem(
          SECTION_STORAGE_PREFIX + sectionId,
          detailsEl.open ? "open" : "closed"
        );
      };
    }(item.id, item.el));
  }
}

function render() {
  if (!state.data) {
    return;
  }

  var slice = sessionUserSlice();
  var config = (slice && slice.config) || {};
  var sessionUser = getSessionUserId();
  var users = state.data.users || [];
  var i, user, activeLabel;

  renderMusicianSelect();
  renderTrackSelect(els.vocalTrack, state.data.folder_tracks, config.vocal_guid, state.data.tracks);
  renderTrackSelect(els.instrumentTrack, state.data.folder_tracks, config.instrument_guid, state.data.tracks);
  renderTrackSelect(els.monitorTrack, state.data.monitor_tracks, config.monitor_guid, state.data.tracks);

  activeLabel = sessionUser;
  for (i = 0; i < users.length; i++) {
    user = users[i];
    if (user.id === sessionUser) {
      activeLabel = user.display_name || user.id;
      break;
    }
  }

  els.projectMeta.textContent =
    "Band member: " +
    activeLabel +
    " · Project: " +
    state.data.project_name +
    " · Storage: " +
    ((slice && slice.storage_path) || "—");
  renderSnapshots();
  renderLiveFx();

  if (!els.musiciansModal.hidden) {
    renderMusiciansModal();
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatDebugJson(data) {
  return JSON.stringify(data, null, 2);
}

function debugModalNote(data) {
  var parts = [];
  var tracks = (data && data.snapshot && data.snapshot.tracks) || [];
  var i, track, truncated;

  if (data && data.user_id) {
    parts.push("Musician: " + data.user_id);
  }
  if (data && data.storage_path) {
    parts.push("Storage: " + data.storage_path);
  }
  if (data && data.fx_chains_omitted) {
    parts.push("FX chains omitted (payload too large for web bridge). Byte lengths are still shown.");
  }

  truncated = false;
  for (i = 0; i < tracks.length; i++) {
    track = tracks[i];
    if (track.fx_chain_truncated || (track.fx_chain_byte_length > 0 && !track.fx_chain)) {
      truncated = true;
      break;
    }
  }
  if (truncated) {
    parts.push("FX chains are truncated in this preview. Enable larger preview or inspect snapshots.json on disk for full data.");
  }

  return parts.join(" · ");
}

function openJsonModal() {
  els.jsonModal.hidden = false;
  document.body.style.overflow = "hidden";
}

function closeJsonModal() {
  els.jsonModal.hidden = true;
  document.body.style.overflow = "";
}

function loadSnapshotDebugJson() {
  var name = state.selectedName;

  if (!name) {
    showMessage(COPY.toastPickPresetToInspect, false);
    return;
  }

  els.jsonModalTitle.textContent = "Snapshot JSON: " + name;
  els.jsonModalNote.textContent = "Loading from REAPER…";
  els.jsonModalContent.textContent = "Loading…";
  openJsonModal();

  return sendCommand({
    action: "get_snapshot",
    name: name,
    full_fx: els.jsonModalFullFx.checked,
  })
    .then(function (response) {
      var data = response.data;
      if (!data) {
        throw new Error("Bridge returned no snapshot data.");
      }
      els.jsonModalNote.textContent = debugModalNote(data);
      els.jsonModalContent.textContent = formatDebugJson(data);
    })
    .catch(function (err) {
      els.jsonModalNote.textContent = "Could not load snapshot JSON.";
      els.jsonModalContent.textContent = err.message || String(err);
    });
}

function onTrackConfigChanged() {
  clearMessage();
  saveTrackConfig()
    .then(function (response) {
      showMessage(response.message, true);
      requestState();
    })
    .catch(function (err) {
      showMessage(err.message, false);
    });
}

function bindEvents() {
  els.musicianSelect.onchange = function () {
    switchMusician(els.musicianSelect.value);
  };

  els.manageMusiciansBtn.onclick = function () {
    openMusiciansModal();
  };

  els.musiciansModalClose.onclick = closeMusiciansModal;
  els.musiciansModal.querySelectorAll("[data-close-musicians-modal]").forEach(function (node) {
    node.onclick = closeMusiciansModal;
  });

  els.addMusicianBtn.onclick = function () {
    var name = els.newMusicianName.value.trim();
    if (!name) {
      showMessage(COPY.toastEnterMusicianName, false);
      return;
    }
    clearMessage();
    sendCommand({ action: "create_user", display_name: name })
      .then(function (response) {
        if (response.data && response.data.user_id) {
          setSessionUserId(response.data.user_id);
        }
        els.newMusicianName.value = "";
        showMessage(response.message, true);
        requestState();
      })
      .catch(function (err) {
        showMessage(err.message, false);
      });
  };

  els.vocalTrack.onchange = onTrackConfigChanged;
  els.instrumentTrack.onchange = onTrackConfigChanged;
  els.monitorTrack.onchange = onTrackConfigChanged;

  els.captureBtn.onclick = function () {
    var name = els.snapshotName.value.trim();
    if (!name) {
      showMessage(COPY.toastEnterPresetName, false);
      return;
    }
    clearMessage();
    sendCommand({ action: "capture", name: name })
      .then(function (response) {
        state.selectedName = name;
        showMessage(response.message, true);
        requestState();
      })
      .catch(function (err) {
        showMessage(err.message, false);
      });
  };

  els.updateBtn.onclick = function () {
    if (!state.selectedName) {
      showMessage(COPY.toastPickPresetToUpdate, false);
      return;
    }
    clearMessage();
    sendCommand({ action: "update", name: state.selectedName })
      .then(function (response) {
        showMessage(response.message, true);
        requestState();
      })
      .catch(function (err) {
        showMessage(err.message, false);
      });
  };

  els.loadBtn.onclick = function () {
    loadSnapshot(state.selectedName);
  };

  els.deleteBtn.onclick = function () {
    if (!state.selectedName) {
      showMessage(COPY.toastPickPresetToDelete, false);
      return;
    }
    if (!confirm('Delete snapshot "' + state.selectedName + '"?')) {
      return;
    }
    clearMessage();
    sendCommand({ action: "delete", name: state.selectedName })
      .then(function (response) {
        state.selectedName = "";
        els.snapshotName.value = "";
        showMessage(response.message, true);
        requestState();
      })
      .catch(function (err) {
        showMessage(err.message, false);
      });
  };

  els.renameBtn.onclick = function () {
    var newName;
    if (!state.selectedName) {
      showMessage(COPY.toastPickPresetToRename, false);
      return;
    }
    newName = prompt("New snapshot name:", state.selectedName);
    if (!newName || newName === state.selectedName) {
      return;
    }
    clearMessage();
    sendCommand({ action: "rename", name: state.selectedName, new_name: newName })
      .then(function (response) {
        state.selectedName = newName;
        els.snapshotName.value = newName;
        showMessage(response.message, true);
        requestState();
      })
      .catch(function (err) {
        showMessage(err.message, false);
      });
  };

  els.filterInput.oninput = renderSnapshots;
  els.filterInput.addEventListener("click", function (event) {
    event.stopPropagation();
  });
  els.filterInput.addEventListener("keydown", function (event) {
    event.stopPropagation();
  });

  els.debugJsonBtn.onclick = function () {
    clearMessage();
    loadSnapshotDebugJson();
  };

  els.jsonModalClose.onclick = closeJsonModal;
  els.jsonModalReload.onclick = function () {
    loadSnapshotDebugJson();
  };
  els.jsonModalCopy.onclick = function () {
    var text = els.jsonModalContent.textContent || "";
    if (!text || text === "Loading…") {
      return;
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        showMessage("JSON copied to clipboard.", true);
      });
      return;
    }
    showMessage("Clipboard copy is not available in this browser.", false);
  };
  els.jsonModalFullFx.onchange = function () {
    if (!els.jsonModal.hidden) {
      loadSnapshotDebugJson();
    }
  };

  els.jsonModal.querySelectorAll("[data-close-modal]").forEach(function (node) {
    node.onclick = closeJsonModal;
  });

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape") {
      if (!els.musiciansModal.hidden) {
        closeMusiciansModal();
      } else if (!els.jsonModal.hidden) {
        closeJsonModal();
      }
    }
  });
}

function boot() {
  initElements();
  applyStaticTooltips();
  setConnection(false, COPY.connecting);
  restoreSectionState();
  bindSectionPersistence();
  bindEvents();
  wwr_start();
  wwr_req_recur("GET/PROJEXTSTATE/" + WEB_SECTION + "/state", 1500);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", boot);
} else {
  boot();
}
