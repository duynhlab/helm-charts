# Instructions for AI Agents

The following guidelines apply to all files in this repository.

## Repository overview

This is a Helm charts repository for duynhlab. Charts are published via the repo release and validation workflow.

## Chart layout

- All charts live under `charts/`.
- Each chart has its own folder, such as `charts/mop`, `charts/duynh`, `charts/slo`, `charts/vm-rules`.
- The folder name should match the chart name in that chart's `Chart.yaml`.
- Each chart follows standard Helm structure (`Chart.yaml`, `values.yaml`, `templates/`).
- Keep each change scoped to the relevant chart unless the task explicitly spans more than one chart.

## Feature implementation workflow

Most agent tasks in this repository are chart feature changes. For these tasks:

1. Identify the affected chart under `charts/<chart>/` and keep the change scoped there.
2. Read the relevant `Chart.yaml`, `values.yaml`, templates, helpers, and existing tests before editing.
3. Implement the feature using the chart's existing values and template patterns.
4. If `values.yaml` changes in a schema-enabled chart, update the schema comments and regenerate `values.schema.json`.
5. Add or update focused Helm unit test coverage for the rendered behavior behind the feature.
6. Bump the chart version in `Chart.yaml` according to SemVer when the change is a chart change.
7. Run the relevant validation command before finishing.

Ask the user for clarification only when the intended chart, feature behavior, or compatibility impact cannot be inferred from the request and local context.

## Values schema

Some charts use `helm-values-schema-json` patterns such as `# @schema` comments and `values.schema.json` generation.

When changing `values.yaml` in a schema-enabled chart:

- Keep nearby `# @schema` annotations intact and update them when needed.
- Preserve draft-07 compatibility for generated JSON Schema output.
- Regenerate `values.schema.json` and include it in the change.
- Add or update test coverage for the affected rendered behavior.

## Validation

Use the smallest relevant check before declaring the task complete.

```bash
make lint CHART=charts/<chart>
make template CHART=charts/<chart>
make unittest CHART=charts/<chart>
make check-rules
make lint-all
```

Typical usage:

- `make lint CHART=charts/mop`
- `make template CHART=charts/duynh`
- `make check-rules` for `charts/vm-rules`
- `make lint-all` for broader repo-wide validation

## Contributing conventions

- Keep changes minimal and chart-aware.
- Preserve backward compatibility unless the task is explicitly breaking.
- Keep `values.yaml`, templates, tests, examples, and generated docs in sync.
- Do not change versions or release metadata unless the task explicitly requires it.
- Use `Makefile` as the source of truth for validation commands.
- For generated README files, prefer the project command instead of manual drift.

## Final check

Good changes in this repo should have:

- a focused diff,
- the relevant `helm lint` / `helm template` validation passing,
- no obvious YAML or template breakage,
- updated tests or examples when the change affects behavior.
