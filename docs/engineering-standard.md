# Engineering Standard

Updated: `2026-04-20 14:55 CST`

## 1. Baseline

Subsequent development for `go-collector` follows the engineering direction described in OpenAI's Harness Engineering article:

- [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)

This repository adopts the following practical rules.

## 2. Working Rules

1. The repository is the system of record.
- Runtime behavior, current constraints, known incidents, and active plans must be written into repository Markdown files.
- Do not leave critical operational knowledge only in chat history or only on the server.

2. Prefer executable validation over assumption.
- For collector changes, validate by `go test ./...`, targeted SQL checks, and server-side log verification.
- For production-path changes, record the exact process, config, log path, and observed result.

3. Optimize the full chain, not a single statement.
- Database write issues must be analyzed at the task-line level:
  - producer concurrency
  - sink serialization
  - transaction size
  - table hot keys
  - coexistence of old and new processes
- Do not treat `1205/1213` as isolated SQL bugs unless chain-level evidence supports that conclusion.

4. Separate steady-state design from temporary containment.
- Temporary mitigations such as chunk reduction, retry, or lowered worker counts must be labeled as containment.
- Root-cause fixes must change the write model, task ownership, or runtime guardrails.

5. Prefer single ownership for hot tables.
- `olt_onu_last` and `olt_octets_last` are hot tables.
- Any new feature touching them must first answer:
  - who is the only writer path
  - how duplicate processes are prevented
  - how write contention is observed

6. Preserve operational clarity.
- Task lines must be visible in `collector_task_overview` and `collector_task_detail`.
- New task lines should not be introduced without:
  - a clear enable switch
  - a single task key
  - status counters
  - error capture

7. Treat long-tail devices as explicit backlog.
- Slow or incompatible devices must be documented with:
  - device id
  - region
  - model
  - IP
  - community
  - observed failure mode
- Do not repeatedly rediscover the same failures without first checking existing records.

## 3. Current Design Implications

Based on the current collector architecture, the following decisions apply now:

1. Duplicate collector processes are not acceptable.
- Startup now uses a single-instance lock file under `./run/collector.lock`.
- Any future deployment or script must preserve this behavior.

2. `ONU` and `octets` bottlenecks must be approached as a sink design problem.
- First check whether more than one writer process exists.
- Then inspect hot-table transaction duration.
- Only after that consider SQL-level micro-optimization.

3. External-source degradation is part of normal operation.
- `onu_external` may degrade per source.
- Fallback state must be recorded in `collector_task_detail`.
- Do not silently modify static device switches to handle temporary external failures.

## 4. Documentation Targets

Changes in the following areas must update Markdown documentation in the same change set:

- task-line behavior
- database write model
- runtime status
- abnormal device list
- deployment guardrails

Primary runtime record file:

- `/AGENTS.md`
