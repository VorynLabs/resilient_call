# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-12

### Added

- `ResilientCall.call` — wraps any block with configurable retry and optional
  circuit-breaker protection.
- Retry engine with `:exponential`, `:linear`, `:fixed`, and custom lambda
  backoff strategies, plus jitter and a `max_wait` cap.
- `on:` option to retry only the listed exception classes, propagating others
  immediately.
- Named, thread-safe circuit breaker — `Circuit` state machine plus the
  `CircuitBreaker` registry — with `threshold`, `reset_timeout`, and half-open
  probing.
- `fallback:` executed while the circuit is open; `CircuitOpenError` raised when
  no fallback is set.
- Lifecycle callbacks: `on_retry`, `on_failure`, and `on_success`.
- Global defaults via `ResilientCall.configure` and reusable named option sets
  via `ResilientCall.define_profile`.
- Option precedence: inline options > profile > global config > gem defaults.
- `ResilientCall::Mixin` with the `resilient_method` macro to declare resilience
  at the method level.
- Error classes `ResilientCall::CircuitOpenError` and
  `ResilientCall::RetriesExhaustedError` (the latter preserves the native
  `#cause` chain).

[Unreleased]: https://github.com/VorynLabs/resilient_call/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/VorynLabs/resilient_call/releases/tag/v0.1.0
