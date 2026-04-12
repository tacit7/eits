# Context Window Calculation

How the DM page calculates and displays context window usage.

## Data Sources

Context is extracted from the most recent message in the session that contains usage data. Two message formats are handled:

### Claude CLI (camelCase)

Messages with `metadata.model_usage` — a map keyed by model name (e.g. `"claude-opus-4-6"`):

```json
{
  "model_usage": {
    "claude-opus-4-6": {
      "inputTokens": 23,
      "cacheReadInputTokens": 584482,
      "cacheCreationInputTokens": 33263,
      "contextWindow": 200000
    }
  }
}
```

`contextWindow` comes from the CLI response. Falls back to `200_000` if absent.

### Anubis / Streaming (snake_case)

Messages with `metadata.usage`:

```json
{
  "usage": {
    "input_tokens": 1,
    "cache_read_input_tokens": 49383,
    "cache_creation_input_tokens": 166
  }
}
```

Context window is hardcoded to `200_000` — Anubis does not report it.

## Calculation

```
used = input_tokens + cache_read_input_tokens + cache_creation_input_tokens
pct  = min(used / context_window * 100, 100.0)
```

`pct` is clamped to `100.0` because `cache_read_input_tokens` can exceed `context_window` on long-running sessions (e.g. 38-round anti-pattern agent: ~1360% raw), which would otherwise produce absurd display values.

## Display

Rendered in `composer.ex` in the message toolbar:

| pct         | Color                     |
|-------------|---------------------------|
| < 60%       | `text-base-content/30`    |
| 60% – 80%   | `text-warning/70`         |
| ≥ 80%       | `text-error/70`           |

Tooltip shows: `{used} / {context_window} tokens used`.

Hidden entirely when `context_window == 0` (no usage data yet).

## Source Files

- Extraction: `lib/eye_in_the_sky_web/live/dm_live/tab_helpers.ex` — `extract_context_window/1`
- Display: `lib/eye_in_the_sky_web/components/dm_page/composer.ex`
