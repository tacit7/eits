# CLI retries

Set `EITS_RETRY=0` in the process environment to make the Rust CLI attempt each
HTTP request once, without retry backoff:

```sh
EITS_RETRY=0 eits tasks list
```

When unset or set to any other value, the existing policy remains: up to four
attempts for connection errors, timeouts, and HTTP 429, 502, 503, or 504, with
exponential backoff and jitter. `EITS_RETRY_BASE_MS` still controls the initial
backoff (default: 2000 milliseconds). Long-poll requests already use one attempt.

The opt-out does not shorten the existing request timeout or change error JSON
or exit codes: connection failures exit 3 and HTTP errors exit 1. It applies to
the Rust HTTP client, not commands delegated to the legacy fallback.
