-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause
-- Keep the request loop native: response callbacks force wrk to parse/copy
-- bodies and can make the generator the bottleneck. Canonical 200 URLs and
-- X-GPForum-Cache are verified separately before and after each measurement.
function done(summary, latency, requests)
    local errors = summary.errors
    local transport = errors.connect + errors.read + errors.write + errors.timeout
    local duration = summary.duration / 1000000
    io.write(string.format(
        '\nGPFORUM_WRK {"completed":%d,"http_errors":%d,"transport_errors":%d,' ..
        '"duration_seconds":%.6f,"requests_per_second":%.6f,' ..
        '"p50_ms":%.6f,"p95_ms":%.6f,"p99_ms":%.6f}\n',
        summary.requests, errors.status, transport, duration,
        duration > 0 and summary.requests / duration or 0,
        latency:percentile(50) / 1000, latency:percentile(95) / 1000,
        latency:percentile(99) / 1000))
end
