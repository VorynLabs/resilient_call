# resilient_call

[![Gem Version](https://img.shields.io/gem/v/resilient_call.svg)](https://rubygems.org/gems/resilient_call)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-red.svg)](https://www.ruby-lang.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> Retry with exponential backoff and a circuit breaker for Ruby — zero dependencies.

`resilient_call` wraps any block of code with configurable retries (exponential,
linear, fixed, or custom backoff) and a named circuit breaker that protects your
system when an external service is consistently failing. It works with plain Ruby
and Rails, relies only on the standard library, and is thread-safe.

## Installation

Add it to your `Gemfile`:

```ruby
gem "resilient_call"
```

Then run `bundle install`, or install it directly:

```bash
gem install resilient_call
```

## Quick start

```ruby
require "resilient_call"

result = ResilientCall.call { ExternalApi.fetch }
```

That single call retries `ExternalApi.fetch` on failure using the default
exponential backoff, returning the result as soon as it succeeds.

## Usage

### Basic retry

```ruby
ResilientCall.call(retries: 3, base_wait: 0.5) do
  HttpClient.get("https://api.example.com/status")
end
```

If the block keeps failing past the configured attempts, `ResilientCall.call`
raises `ResilientCall::RetriesExhaustedError`.

### Retry strategies

Control the wait between attempts with `wait:`. The `attempt` number is 1-based.

| `wait:`        | Behavior                       | Example (`base_wait: 0.5`) |
| -------------- | ------------------------------ | -------------------------- |
| `:exponential` | `base_wait * (2 ** attempt)`   | 1s, 2s, 4s, 8s…            |
| `:linear`      | `base_wait * attempt`          | 0.5s, 1s, 1.5s, 2s…        |
| `:fixed`       | `base_wait`                    | 0.5s, 0.5s, 0.5s…          |
| `->(n) { … }`  | custom, receives `attempt`     | any logic                  |

With `jitter: true` (the default), a random `rand(0..base_wait * 0.3)` is added
to the computed wait before capping it at `max_wait`. This avoids the thundering
herd problem when many clients retry at once.

```ruby
ResilientCall.call(wait: :exponential, base_wait: 0.5, max_wait: 30.0, jitter: true) do
  PaymentGateway.charge(amount: 100)
end
```

### Selecting which errors trigger a retry

```ruby
ResilientCall.call(on: [Net::OpenTimeout, Net::ReadTimeout]) do
  HttpClient.get(url)
end
```

Only the listed exception classes are retried; anything else propagates
immediately. The default is `[StandardError]`.

### Circuit breaker

Pass `circuit:` to protect a dependency with a named circuit breaker. After
`threshold` consecutive failures the circuit opens and stops sending requests
until `reset_timeout` seconds have elapsed, when it allows a single probe.

```ruby
ResilientCall.call(circuit: :stripe, threshold: 5, reset_timeout: 30) do
  StripeClient.charge(amount: 100)
end
```

While the circuit is open, `ResilientCall.call` raises
`ResilientCall::CircuitOpenError` (unless a `fallback` is given).

### Fallback

```ruby
ResilientCall.call(circuit: :stripe, fallback: -> { CachedResult.last }) do
  StripeClient.charge(amount: 100)
end
```

When the circuit is open the `fallback` runs instead of the block, and its
return value becomes the result of the call.

### Callbacks

```ruby
ResilientCall.call(
  on_retry:   ->(attempt, error) { Rails.logger.warn("retry ##{attempt}: #{error.message}") },
  on_failure: ->(error)          { Sentry.capture_exception(error) },
  on_success: ->(result, tries)  { StatsD.increment("ok", tags: ["tries:#{tries}"]) }
) do
  StripeClient.charge(amount: 100)
end
```

### Global configuration

Set defaults once — in `config/initializers/resilient_call.rb` on Rails, or at
boot in plain Ruby. Options passed to `.call` always override these.

```ruby
ResilientCall.configure do |c|
  c.retries       = 3
  c.wait          = :exponential
  c.base_wait     = 0.5
  c.max_wait      = 30.0
  c.jitter        = true
  c.on            = [StandardError]

  c.threshold     = 5
  c.reset_timeout = 60

  c.on_retry      = ->(attempt, error) { Rails.logger.warn("[resilient_call] retry ##{attempt}: #{error.message}") }
  c.on_failure    = ->(error)          { Rails.logger.error("[resilient_call] failed: #{error.message}") }
end
```

### Reusable profiles

Profiles are named option sets. They merge over the global defaults and can be
overridden inline. Precedence: **inline options > profile > global config > gem defaults**.

```ruby
ResilientCall.define_profile :payment,
  retries: 3, wait: :exponential, circuit: :stripe, threshold: 5, reset_timeout: 30

ResilientCall.define_profile :fast_api,
  retries: 1, wait: :fixed, base_wait: 0.1, on: [Net::OpenTimeout]

ResilientCall.call(profile: :payment) { StripeClient.charge(amount: 100) }
ResilientCall.call(profile: :fast_api, retries: 2) { SlackNotifier.ping(message) }
```

### Service object mixin

Declare resilience at the method level — transparent to the caller.

```ruby
class PaymentService
  include ResilientCall::Mixin

  def charge(amount)
    StripeClient.charge(amount: amount)
  end
  resilient_method :charge, profile: :payment

  def refund(charge_id)
    StripeClient.refund(charge_id)
  end
  resilient_method :refund, retries: 2, circuit: :stripe
end

PaymentService.new.charge(100) # retries + circuit breaker applied automatically
```

`resilient_method` must be called after the method is defined. It forwards
positional arguments, keyword arguments, and blocks unchanged.

### Inspecting circuits at runtime

```ruby
circuit = ResilientCall::CircuitBreaker[:stripe]

circuit.state          # => :closed | :open | :half_open
circuit.failure_count  # => Integer
circuit.last_failure   # => Exception or nil
circuit.opened_at      # => Time or nil
circuit.reset!         # force it closed — handy in a console, rake task, or test

ResilientCall::CircuitBreaker.reset_all! # reset every registered circuit
```

## Error reference

### `ResilientCall::CircuitOpenError`

Raised when the circuit is open and no `fallback` is set.

```ruby
rescue ResilientCall::CircuitOpenError => e
  e.circuit_name # => :stripe
  e.opens_at     # => Time the circuit opened
  e.retry_after  # => Integer seconds estimated until half-open
  e.last_error   # => the last exception that contributed to opening
end
```

### `ResilientCall::RetriesExhaustedError`

Raised when every retry has been consumed without success.

```ruby
rescue ResilientCall::RetriesExhaustedError => e
  e.attempts # => number of attempts made
  e.cause    # => the last captured exception (native Ruby #cause)
end
```

## Configuration reference

| Option          | Default           | Description                                              |
| --------------- | ----------------- | -------------------------------------------------------- |
| `retries`       | `3`               | Attempts after the first failure                         |
| `wait`          | `:exponential`    | Backoff strategy (`:exponential`/`:linear`/`:fixed`/Proc)|
| `base_wait`     | `0.5`             | Base seconds for the backoff calculation                 |
| `max_wait`      | `30.0`            | Upper bound for the backoff, in seconds                  |
| `jitter`        | `true`            | Add random noise to the wait                             |
| `on`            | `[StandardError]` | Exception classes that trigger a retry                   |
| `circuit`       | `nil`             | Named circuit (Symbol); no circuit breaker without it    |
| `threshold`     | `5`               | Consecutive failures before the circuit opens            |
| `reset_timeout` | `60`              | Seconds in the open state before a half-open probe       |
| `fallback`      | `nil`             | Callable run when the circuit is open                    |
| `on_retry`      | `nil`             | `->(attempt, error)` called on each retry                |
| `on_failure`    | `nil`             | `->(error)` called when attempts are exhausted           |
| `on_success`    | `nil`             | `->(result, attempts)` called on success                 |

## Roadmap

| Version | Feature                                                          |
| ------- | --------------------------------------------------------------- |
| `v0.2`  | Pluggable storage for circuit state (Redis for multi-process)   |
| `v0.3`  | `ActiveSupport::Notifications` instrumentation and metrics      |
| `v0.4`  | Mountable Rack dashboard for live circuit state                 |
| `v0.5`  | Native timeout integrated into the retry loop                   |
| `v1.0`  | Stable API, full documentation, published benchmarks            |

## Contributing

Bug reports and pull requests are welcome on GitHub at
<https://github.com/VorynLabs/resilient_call>. Run the test suite with
`bundle exec rspec` before submitting.

## License

Released under the [MIT License](LICENSE).
