# ADR 0001: One repository for the whole learning platform

Status: Accepted

## Context
The projects (secure lake, ADF ingestion, Databricks lakehouse, streaming, serving,
governance, operations, capstone) build on each other and share infrastructure modules.

## Decision
Use a single repository with one folder per project, shared modules in `infra/modules/`,
and shared decisions in `docs/adr/`.

## Alternatives considered
- One repository per project: independent, but duplicates shared modules and hides the
  end-to-end story.

## Consequences
- Easy sharing and one CI/CD setup using path filters.
- Needs clear folder ownership and path-based workflows as the repo grows.
