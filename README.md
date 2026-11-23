# Pulumi Viewer

A read-only web viewer for **Pulumi self-managed (DIY) backends**: S3 buckets,
local `file://` state, and S3 on a local AWS emulator (Floci, LocalStack, AWS Emulator).
You keep your backend and get stacks, a resource graph, resource details and update history
without Pulumi Cloud.

Stack: Elixir, Phoenix LiveView, [Ash](https://ash-hq.org) (state is modelled as Ash resources),
Tailwind/daisyUI, [xyflow](https://xyflow.com) + [ELK](https://eclipse.dev/elk/) for the graph,
and [Tidewave](https://tidewave.ai) in dev.

## Run

```sh
mise install && mise run setup
mise run serve                                   # demo fixture state, http://localhost:4077
mise run serve:aws -- my-profile s3://my-pulumi-state
mise run serve:emulator -- s3://my-pulumi-state http://localhost:4566
PULUMI_BACKEND_URL=file://~/.pulumi-state mise run serve
```

The backend URL uses the same form as `pulumi login`. The viewer only lists and reads objects
(`s3:ListBucket`, `s3:GetObject`); it never writes. Secret values stay encrypted and show as `[secret]`.

## What it reads

| Key | Use |
| --- | --- |
| `.pulumi/stacks/<project>/<stack>.json[.gz]` | current checkpoint: resources, parents, dependencies, providers |
| `.pulumi/stacks/<stack>.json[.gz]` | legacy (non project-scoped) stacks |
| `.pulumi/history/<project>/<stack>/*.history.json` | update history |

## Layout

- `lib/pulumi_viewer/pulumi/` – pure parsers: key layout, checkpoint, history, graph.
- `lib/pulumi_viewer/storage/` – `Local` and `S3` readers behind one behaviour.
- `lib/pulumi_viewer/infra/` – Ash domain `PulumiViewer.Infra` (`Stack`, `Resource`, `Update`).
- `assets/js/resource_graph.jsx` – xyflow graph, mounted as a LiveView hook.

## Roadmap

- Pending changes: render saved `pulumi preview --json` output.
- Drift and coverage: compare Pulumi state with CloudFormation stacks and the live AWS inventory.
- Policy (CrossGuard results) and FinOps (Cost Explorer) views.

Prior art worth reading: [mlops-club/pulumi-ui](https://github.com/mlops-club/pulumi-ui),
[state-db/statedb](https://github.com/state-db/statedb),
[pandada8/pulumi-api-backend](https://github.com/pandada8/pulumi-api-backend).

## License

MIT
