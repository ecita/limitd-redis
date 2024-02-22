[![Build Status](https://travis-ci.org/auth0/limitd-redis.svg?branch=master)](https://travis-ci.org/auth0/limitd-redis)

`limitd-redis` is client for limits on top of `redis` using [Token Buckets](https://en.wikipedia.org/wiki/Token_bucket).
It's a fork from [LimitDB](https://github.com/limitd/limitdb).

## Installation

```
npm i limitd-redis
```

## Configure

Create an instance of `limitd-redis` as follows:

```js
const Limitd = require('limitd-redis');

const limitd = new Limitd({
  uri: 'localhost',
  //or
  nodes: [{
    port: 7000,
    host: 'localhost'
  }],
  buckets: {
    ip: {
      size: 10,
      per_second: 5
    }
  },
  prefix: 'test:',
  ping: {
    interval: 1000,
    maxFailedAttempts: 5,
    reconnectIfFailed: true
  }
});
```

Options available:

- `uri` (string): Redis Connection String.
- `nodes` (array): [Redis Cluster Configuration](https://github.com/luin/ioredis#cluster).
- `buckets` (object): Setup your bucket types.
- `prefix` (string): Prefix keys in Redis.
- `ping` (object): Configure ping to Redis DB.

Buckets:

- `size` (number): is the maximum content of the bucket. This is the maximum burst you allow.
- `per_interval` (number): is the amount of tokens that the bucket receive on every interval.
- `interval` (number): defines the interval in milliseconds.
- `unlimited` (boolean = false): unlimited requests (skip take).
- `skip_n_calls` (number): take will go to redis every `n` calls instead of going in every take.
- `elevated_limits` (object): elevated limits configuration that kick in when the bucket is empty. Consider it as an override that kick in when the bucket is empty.

Ping:

- `interval` (number): represents the time between two consecutive pings. Default: 3000.
- `maxFailedAttempts` (number): is the allowed number of failed pings before declaring the connection as dead. Default: 5.
- `reconnectIfFailed` (boolean): indicates whether we should try to reconnect is the connection is declared dead. Default: true.

You can also define your rates using `per_second`, `per_minute`, `per_hour`, `per_day`. So `per_second: 1` is equivalent to `per_interval: 1, interval: 1000`.

If you omit `size`, limitdb assumes that `size` is the value of `per_interval`. So `size: 10, per_second: 10` is the same than `per_second: 10`.

If you don't specify a filling rate with `per_interval` or any other `per_x`, the bucket is fixed and you have to manually reset it using `PUT`.

## Overrides
You can also define `overrides` inside your type definitions as follows:

```js
buckets = {
  ip: {
    size: 10,
    per_second: 5,
    overrides: {
      '127.0.0.1': {
        size: 100,
        per_second: 50
      }
    }
  }
}
```

In this case the specific bucket for `127.0.0.1` of type `ip` will have a greater limit.

It is also possible to define overrides by regex:

```js
overrides: {
  'local-ips': {
    match:      /192\.168\./
    size:       100,
    per_second: 50
  }
}
```

It's possible to configure expiration of overrides:

```js
overrides: {
  '54.32.12.31': {
    size:       100,
    per_second: 50,
    until:      new Date(2016, 4, 1)
  }
}
```

## ERL (Elevated Rate Limits)
ERL is a feature that allows you to define a different set of limits that kick in when the bucket is empty.
You can configure elevated limits inside your type definitions as follows:

```js
buckets = {
  ip: {
    size: 10,
    per_second: 5,
    elevated_limits: {
      size: 100, // new bucket size. already used tokens will be deducted from current bucket content upon ERL activation.
      per_second: 50, // new bucket refill ate
      erl_activation_period_mins: 5, // for how long the ERL configuration should remain active
    }
  }
}
```

## Breaking changes from `Limitdb`

* Elements will have a default TTL of a week unless specified otherwise.

## TAKE

```js
limitd.take(type, key, [count], (err, result) => {
  console.log(result);
});
```

`limitd.take` takes the following arguments:

-  `type`: the bucket type.
-  `key`: the identifier of the bucket.
-  `count`: the amount of tokens you need. This is optional and the default is 1.
-  `configOverride`: caller-provided bucket configuration for this operation
-  `erlIsActiveKey`: the identifier of the ERL activation for the bucket. Must be passed for buckets that have ERL configured.
The result object has:

-  `conformant` (boolean): true if the requested amount is conformant to the limit.
-  `remaining` (int): the amount of remaining tokens in the bucket.
-  `reset` (int / unix timestamp): unix timestamp of the date when the bucket will be full again.
-  `limit` (int): the size of the bucket.
-  `erl_activated` (boolean): true if the bucket has ERL activated at the time of the request. Only returned for buckets that have ERL configured.

## PUT

You can manually reset a fill a bucket using PUT:

```js
limitd.put(type, key, [count], (err, result) => {
  console.log(result);
});
```

`limitd.put` takes the following arguments:

-  `type`: the bucket type.
-  `key`: the identifier of the bucket.
-  `count`: the amount of tokens you want to put in the bucket. This is optional and the default is the size of the bucket.
-  `configOverride`: caller-provided bucket configuration for this operation

## Overriding Configuration at Runtime
Since the method of storing overrides for buckets in memory does not scale to a large number, limitd-redis provides a way for callers to pass in configuration from an external data store.  The shape of this `configOverride` parameter (available on `take`, `put`, `get`, and `wait`) is exactly the same as `Buckets` above ^.

An example configuration override call might look like this:

```js
const configOverride = {
  size: 45,
  per_hour: 15
}
// take one
limitd.take(type, key, { configOverride }, (err, result) => {
  console.log(result);
}
// take multiple
limitd.take(type, key, { count: 3, configOverride }, (err, result) => {
  console.log(result);
}););
```

Config overrides follow the same rules as Bucket configuration elements with respect to default size when not provided and ttl.

## Author

[Auth0](auth0.com)

## License

This project is licensed under the MIT license. See the [LICENSE](LICENSE) file for more info.
