local tokens_per_ms               = tonumber(ARGV[1])
local bucket_size                 = tonumber(ARGV[2])
local tokens_to_take              = tonumber(ARGV[3])
local ttl                         = tonumber(ARGV[4])
local drip_interval               = tonumber(ARGV[5])
local erl_tokens_per_ms           = tonumber(ARGV[6])
local erl_bucket_size             = tonumber(ARGV[7])
local erl_activation_period_mins  = tonumber(ARGV[8])

-- the key to use for pulling last bucket state from redis
local lastBucketStateKey = KEYS[1]

-- the key for checking in redis if elevated rate limits (erl) were activated earlier
local erlKey = KEYS[2]
local is_erl_activated = redis.call('EXISTS', erlKey)

-- get current bucket state
local current = redis.pcall('HMGET', lastBucketStateKey, 'd', 'r')
if current.err ~= nil then
    current = {}
end

-- get current time from redis, to be used in new bucket size calculations later
local current_time = redis.call('TIME')
local current_timestamp_ms = current_time[1] * 1000 + current_time[2] / 1000

local function calculateNewBucketContent(current, tokens_per_ms, bucket_size, current_timestamp_ms)
    if current[1] and tokens_per_ms then
        -- drip bucket
        local last_drip = current[1]
        local content = current[2]
        local delta_ms = math.max(current_timestamp_ms - last_drip, 0)
        local drip_amount = delta_ms * tokens_per_ms
        return math.min(content + drip_amount, bucket_size)
    elseif current[1] and tokens_per_ms == 0 then
        -- fixed bucket
        return current[2]
    else
        -- first take of the bucket
        return bucket_size
    end
end

-- Enable verbatim replication to ensure redis sends script's source code to all masters
-- managing the sharded database in a clustered deployment.
-- https://redis.io/docs/interact/programmability/eval-intro/#:~:text=scripts%20debugger.-,Script%20replication,-In%20standalone%20deployments
redis.replicate_commands()

-- calculate new bucket content
local new_content = calculateNewBucketContent(current, tokens_per_ms, bucket_size, current_timestamp_ms)
local enough_tokens = new_content >= tokens_to_take
if enough_tokens and is_erl_activated==0 then
    new_content = math.min(new_content - tokens_to_take, bucket_size)
else
    -- calculate new bucket content based on elevated rate limits
    new_content = calculateNewBucketContent(current, erl_tokens_per_ms, erl_bucket_size, current_timestamp_ms)
    -- if activating erl for first time, refill the bucket with the old bucket size
    if is_erl_activated == 0 then
        new_content = erl_bucket_size - bucket_size
        -- save erl state
        redis.call('SET', erlKey, '1')
        redis.call('EXPIRE', erlKey, erl_activation_period_mins * 60)
        is_erl_activated = 1 -- this will be returned to the caller, so we should set it
    end
    enough_tokens = new_content >= tokens_to_take
    if enough_tokens then
        new_content = math.min(new_content - tokens_to_take, erl_bucket_size)
    end
end

-- save bucket state
redis.call('HMSET', lastBucketStateKey,
            'd', current_timestamp_ms,
            'r', new_content)
redis.call('EXPIRE', lastBucketStateKey, ttl)

local reset_ms = 0
if drip_interval > 0 then
    reset_ms = math.ceil(current_timestamp_ms + (bucket_size - new_content) * drip_interval)
end

return { new_content, enough_tokens, current_timestamp_ms, reset_ms, is_erl_activated }
