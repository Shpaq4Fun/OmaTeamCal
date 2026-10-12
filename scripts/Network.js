// scripts/Network.js
// Reusable XMLHttpRequest wrapper for Quickshell
// .pragma library ensures no QML import warnings

.pragma library

const DEFAULT_TIMEOUT_MS = 10000;

function createXHR() {
    return new XMLHttpRequest();
}

function parseJSON(text) {
    try {
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

function fetchJson(url, callback, options) {
    var opts = options || {};
    var timeoutMs = opts.timeout || DEFAULT_TIMEOUT_MS;
    var headers = opts.headers || {};
    var method = opts.method || "GET";
    var body = opts.body || null;

    var xhr = createXHR();
    xhr.timeout = timeoutMs;

    xhr.open(method, url, true);

    // Default headers
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("User-Agent", "OmaTeamCal/0.1.0 (Quickshell)");

    // Custom headers
    for (var h in headers) {
        if (headers.hasOwnProperty(h)) {
            xhr.setRequestHeader(h, headers[h]);
        }
    }

    xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) {
            var data = parseJSON(xhr.responseText);
            if (data === null) {
                callback(false, "Failed to parse JSON response", xhr.responseText);
            } else {
                callback(true, data, xhr);
            }
        } else {
            var errorMsg = "HTTP " + xhr.status + " " + xhr.statusText;
            try {
                var errData = parseJSON(xhr.responseText);
                if (errData && errData.error && errData.error.message) {
                    errorMsg += ": " + errData.error.message;
                }
            } catch (e) {
                // ignore parse error on error response
            }
            callback(false, errorMsg, xhr);
        }
    };

    xhr.onerror = function() {
        callback(false, "Network error", null);
    };

    xhr.ontimeout = function() {
        callback(false, "Request timeout after " + timeoutMs + "ms", null);
    };

    if (body && typeof body === "object") {
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify(body));
    } else {
        xhr.send(body);
    }

    return xhr;
}

function fetchJsonPost(url, body, callback, options) {
    var opts = options || {};
    opts.method = "POST";
    opts.body = body;
    return fetchJson(url, callback, opts);
}

// Simple in-memory cache for GET requests
var _cache = {};
var _cacheTimestamps = {};
const DEFAULT_CACHE_TTL_MS = 30000; // 30 seconds

function fetchJsonCached(url, callback, options) {
    var opts = options || {};
    var ttl = opts.cacheTtl || DEFAULT_CACHE_TTL_MS;
    var now = Date.now();

    if (_cache[url] && (now - _cacheTimestamps[url]) < ttl) {
        // Return cached data synchronously (it's cached, no need for async)
        callback(true, _cache[url], { cached: true, status: 200 });
        return null; // no xhr returned for cached
    }

    return fetchJson(url, function(success, data, xhr) {
        if (success) {
            _cache[url] = data;
            _cacheTimestamps[url] = Date.now();
        }
        callback(success, data, xhr);
    }, opts);
}

function clearCache(url) {
    if (url) {
        delete _cache[url];
        delete _cacheTimestamps[url];
    } else {
        _cache = {};
        _cacheTimestamps = {};
    }
}

// Export functions (Quickshell JS modules expose all top-level functions)