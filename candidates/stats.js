/**
 * Game play statistics — localStorage-backed
 *
 * Schema per game (key: "mono-stats"):
 * {
 *   "<gameId>": {
 *     plays: number,        // total play count
 *     lastPlayed: number,   // Date.now() of last play
 *     totalTime: number,    // cumulative ms spent playing
 *     likes: number,        // cumulative likes
 *     dislikes: number      // cumulative dislikes
 *   }
 * }
 */
var GameStats = (function() {
  var KEY = "mono-stats";

  function _load() {
    try { return JSON.parse(localStorage.getItem(KEY)) || {}; }
    catch(e) { return {}; }
  }

  function _save(data) {
    localStorage.setItem(KEY, JSON.stringify(data));
  }

  function _defaults() {
    return { plays: 0, lastPlayed: 0, totalTime: 0, likes: 0, dislikes: 0 };
  }

  function _ensure(all, gameId) {
    if (!all[gameId]) all[gameId] = _defaults();
    // migrate old entries missing likes/dislikes
    if (all[gameId].likes == null) all[gameId].likes = 0;
    if (all[gameId].dislikes == null) all[gameId].dislikes = 0;
    return all[gameId];
  }

  /** Get stats for one game */
  function get(gameId) {
    var all = _load();
    return _ensure(all, gameId);
  }

  /** Get stats for all games */
  function getAll() {
    return _load();
  }

  /** Record a new play session start — increments plays, sets lastPlayed */
  function recordStart(gameId) {
    var all = _load();
    _ensure(all, gameId);
    all[gameId].plays += 1;
    all[gameId].lastPlayed = Date.now();
    _save(all);
  }

  /** Add elapsed time (ms) to totalTime */
  function addTime(gameId, ms) {
    if (ms <= 0) return;
    var all = _load();
    _ensure(all, gameId);
    all[gameId].totalTime += ms;
    all[gameId].lastPlayed = Date.now();
    _save(all);
  }

  /** Add a like (cumulative) */
  function like(gameId) {
    var all = _load();
    _ensure(all, gameId);
    all[gameId].likes += 1;
    _save(all);
    return all[gameId];
  }

  /** Add a dislike (cumulative) */
  function dislike(gameId) {
    var all = _load();
    _ensure(all, gameId);
    all[gameId].dislikes += 1;
    _save(all);
    return all[gameId];
  }

  /** Format ms to human-readable string */
  function formatTime(ms) {
    if (ms <= 0) return "--";
    var sec = Math.floor(ms / 1000);
    if (sec < 60) return sec + "s";
    var min = Math.floor(sec / 60);
    sec = sec % 60;
    if (min < 60) return min + "m " + sec + "s";
    var hr = Math.floor(min / 60);
    min = min % 60;
    return hr + "h " + min + "m";
  }

  /** Format lastPlayed timestamp to relative string */
  function formatAgo(ts) {
    if (!ts) return "--";
    var diff = Date.now() - ts;
    var sec = Math.floor(diff / 1000);
    if (sec < 60) return "just now";
    var min = Math.floor(sec / 60);
    if (min < 60) return min + "m ago";
    var hr = Math.floor(min / 60);
    if (hr < 24) return hr + "h ago";
    var day = Math.floor(hr / 24);
    if (day < 30) return day + "d ago";
    return new Date(ts).toLocaleDateString();
  }

  return {
    get: get,
    getAll: getAll,
    recordStart: recordStart,
    addTime: addTime,
    like: like,
    dislike: dislike,
    formatTime: formatTime,
    formatAgo: formatAgo
  };
})();
