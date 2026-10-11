-- SPDX-FileCopyrightText: 2026 Giacomo Picchiarelli
-- SPDX-License-Identifier: BSD-3-Clause
-- Extend the existing metrics writer without response/body callbacks.
local threads = {}
local names = {"thread", "category", "home", "search", "other"}
local allowed = {thread=true, category=true, home=true, search=true, other=true}

function setup(thread)
    threads[#threads + 1] = thread
    thread:set("extreme_offset", #threads - 1)
end

function init(args)
    assert(args[1] and args[1]:match("/benchmarks/wrk%-metrics%.lua$"), "metrics script required")
    extreme_metrics_script = args[1]
    extreme_issued = {}
    if args[2] == "single" then return end
    assert(args[2] == "mixed" and (#args - 2) % 3 == 0, "invalid mixed configuration")
    local requests, buckets = {}, {}
    for i = 3, #args, 3 do
        local name, weight, path = args[i], tonumber(args[i + 1]), args[i + 2]
        assert(allowed[name] and weight and weight >= 0 and weight <= 100 and weight == math.floor(weight), "invalid weight")
        assert(path and path:sub(1, 1) == "/" and not path:find("[%c%s]"), "invalid path")
        extreme_issued[name] = 0
        local formatted = wrk.format("GET", path)
        for _ = 1, weight do
            requests[#requests + 1], buckets[#buckets + 1] = formatted, name
        end
    end
    assert(#requests == 100, "weights must sum to 100")
    local index = extreme_offset or 0
    request = function()
        index = index % #requests + 1
        local name = buckets[index]
        extreme_issued[name] = extreme_issued[name] + 1
        return requests[index]
    end
end

function done(summary, latency, requests)
    local metrics_script = threads[1]:get("extreme_metrics_script")
    dofile(metrics_script)
    local base_done = done
    base_done(summary, latency, requests)
    local counts = {}
    for _, name in ipairs(names) do counts[name] = 0 end
    for _, thread in ipairs(threads) do
        for name, count in pairs(thread:get("extreme_issued") or {}) do
            counts[name] = counts[name] + count
        end
    end
    local errors = summary.errors
    io.write(string.format('\nGPFORUM_EXTREME {"timeouts":%d,"connect_errors":%d,"read_errors":%d,"write_errors":%d,"issued_counts":{"thread":%d,"category":%d,"home":%d,"search":%d,"other":%d}}\n',
        errors.timeout, errors.connect, errors.read, errors.write,
        counts.thread, counts.category, counts.home, counts.search, counts.other))
end
