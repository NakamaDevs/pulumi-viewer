# Run Pulumi Viewer with Docker and Aspire

Pulumi Viewer is published as a multi-arch image (linux/amd64, linux/arm64) on every push to `main`:

| Tag | Meaning |
| --- | --- |
| `ghcr.io/nakamadevs/pulumi-viewer:latest` | newest `main` |
| `ghcr.io/nakamadevs/pulumi-viewer:sha-<commit>` | one exact commit (pin this for repeatable setups) |
| `ghcr.io/nakamadevs/pulumi-viewer:<version>` | a release tag `v<version>` |

Use the image in an [Aspire](https://aspire.dev) AppHost or with plain Docker. You need no Elixir
or Node. To run your own changes, build the `Dockerfile` at the repository root instead (the
"dev version" below).

## Settings

| Variable | Default | Use |
| --- | --- | --- |
| `PULUMI_BACKEND_URL` | bundled demo state | `s3://<bucket>[/prefix]` or `file://<dir>`, same form as `pulumi login` |
| `AWS_REGION` | `us-east-1` | region of the state bucket |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | none | credentials; or an instance role on EC2/ECS |
| `AWS_ENDPOINT_URL` (or `AWS_ENDPOINT_URL_S3`) | none | S3 on an emulator: Floci, LocalStack, AWS Emulator |
| `PORT` | `4000` | HTTP port inside the container |
| `SECRET_KEY_BASE` | random per boot | set it only when you run more than one replica |

The viewer needs only `s3:ListBucket` and `s3:GetObject` on the state bucket. Secret values stay
encrypted and show as `[secret]`. Tidewave is not in the image; it runs only with `mix phx.server`
in dev (turn it off there with `TIDEWAVE=false`).

## Docker

```sh
docker pull ghcr.io/nakamadevs/pulumi-viewer:latest
docker tag ghcr.io/nakamadevs/pulumi-viewer:latest pulumi-viewer   # or: docker build -t pulumi-viewer .

# demo state
docker run --rm -p 4000:4000 pulumi-viewer

# a real bucket, with credentials from an AWS CLI (also SSO) profile
eval "$(aws configure export-credentials --profile my-readonly --format env)"
docker run --rm -p 4000:4000 \
  -e PULUMI_BACKEND_URL=s3://my-pulumi-state \
  -e AWS_REGION -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  pulumi-viewer

# local file state (what `pulumi login file://~/pulumi-state` writes)
docker run --rm -p 4000:4000 -v ~/pulumi-state:/state:ro \
  -e PULUMI_BACKEND_URL=file:///state pulumi-viewer

# S3 on an emulator that runs on the host
docker run --rm -p 4000:4000 \
  -e PULUMI_BACKEND_URL=s3://pulumi-state \
  -e AWS_ENDPOINT_URL=http://host.docker.internal:4566 \
  -e AWS_ACCESS_KEY_ID=test -e AWS_SECRET_ACCESS_KEY=test \
  pulumi-viewer
```

## Aspire

Each sample adds three resources:

- `pulumi-viewer-demo`: the bundled demo state.
- `pulumi-viewer-local`: state in S3 on an emulator container in the same AppHost.
- `pulumi-viewer-dev`: a real bucket, with credentials that come from AppHost parameters.

Each sample uses the published image; the comment above `viewer` shows the dev-version line.
Use one AppHost language; each file is complete.

### TypeScript (`apphost.mts`)

```ts
import { createBuilder } from './.modules/aspire.js';

const builder = await createBuilder();

// Published image. For the dev version use: builder.addDockerfile(name, '../pulumi-viewer')
const viewer = (name: string) =>
  builder
    .addContainer(name, { image: 'ghcr.io/nakamadevs/pulumi-viewer', tag: 'latest' })
    .withHttpEndpoint({ targetPort: 4000 })
    .withExternalHttpEndpoints();

// 1. Demo state, no settings.
await viewer('pulumi-viewer-demo');

// 2. Pulumi state in S3 on a local AWS emulator.
const emulator = await builder
  .addContainer('aws-emulator', { image: 'floci/floci', tag: 'latest' })
  .withHttpEndpoint({ targetPort: 4566, name: 'http' });

await viewer('pulumi-viewer-local')
  .withEnvironment('PULUMI_BACKEND_URL', 's3://pulumi-state')
  .withEnvironment('AWS_ENDPOINT_URL', emulator.getEndpoint('http'))
  .withEnvironment('AWS_ACCESS_KEY_ID', 'test')
  .withEnvironment('AWS_SECRET_ACCESS_KEY', 'test')
  .waitFor(emulator);

// 3. A real bucket. Set the parameters in user secrets or the dashboard.
const accessKey = builder.addParameter('aws-access-key-id', { secret: true });
const secretKey = builder.addParameter('aws-secret-access-key', { secret: true });
const sessionToken = builder.addParameter('aws-session-token', { secret: true });

await viewer('pulumi-viewer-dev')
  .withEnvironment('PULUMI_BACKEND_URL', 's3://my-pulumi-state')
  .withEnvironment('AWS_REGION', 'us-east-1')
  .withEnvironment('AWS_ACCESS_KEY_ID', accessKey)
  .withEnvironment('AWS_SECRET_ACCESS_KEY', secretKey)
  .withEnvironment('AWS_SESSION_TOKEN', sessionToken);

await builder.build().run();
```

### C# (`AppHost.cs`)

```csharp
var builder = DistributedApplication.CreateBuilder(args);

// Published image. For the dev version use: builder.AddDockerfile(name, "../pulumi-viewer")
IResourceBuilder<ContainerResource> Viewer(string name) =>
    builder.AddContainer(name, "ghcr.io/nakamadevs/pulumi-viewer", "latest")
        .WithHttpEndpoint(targetPort: 4000)
        .WithExternalHttpEndpoints();

// 1. Demo state, no settings.
Viewer("pulumi-viewer-demo");

// 2. Pulumi state in S3 on a local AWS emulator.
var emulator = builder.AddContainer("aws-emulator", "floci/floci", "latest")
    .WithHttpEndpoint(targetPort: 4566, name: "http");

Viewer("pulumi-viewer-local")
    .WithEnvironment("PULUMI_BACKEND_URL", "s3://pulumi-state")
    .WithEnvironment("AWS_ENDPOINT_URL", emulator.GetEndpoint("http"))
    .WithEnvironment("AWS_ACCESS_KEY_ID", "test")
    .WithEnvironment("AWS_SECRET_ACCESS_KEY", "test")
    .WaitFor(emulator);

// 3. A real bucket. Set the parameters with `dotnet user-secrets` or the dashboard.
var accessKey = builder.AddParameter("aws-access-key-id", secret: true);
var secretKey = builder.AddParameter("aws-secret-access-key", secret: true);
var sessionToken = builder.AddParameter("aws-session-token", secret: true);

Viewer("pulumi-viewer-dev")
    .WithEnvironment("PULUMI_BACKEND_URL", "s3://my-pulumi-state")
    .WithEnvironment("AWS_REGION", "us-east-1")
    .WithEnvironment("AWS_ACCESS_KEY_ID", accessKey)
    .WithEnvironment("AWS_SECRET_ACCESS_KEY", secretKey)
    .WithEnvironment("AWS_SESSION_TOKEN", sessionToken);

builder.Build().Run();
```

### Go (`apphost.go`)

The Go SDK is generated by `aspire restore` from `aspire.config.json`. Option helper names can
change between Aspire versions; check them with `go doc apphost/modules/aspire`.

```go
package main

import (
	"log"

	"apphost/modules/aspire"
)

func main() {
	builder, err := aspire.CreateBuilder()
	if err != nil {
		log.Fatal(aspire.FormatError(err))
	}

	// Published image. For the dev version use: builder.AddDockerfile(name, "../pulumi-viewer")
	viewer := func(name string) *aspire.ContainerResource {
		return builder.AddContainer(name, "ghcr.io/nakamadevs/pulumi-viewer").
			WithImageTag("latest").
			WithHttpEndpoint(aspire.HttpEndpointTargetPort(4000)).
			WithExternalHttpEndpoints()
	}

	// 1. Demo state, no settings.
	viewer("pulumi-viewer-demo")

	// 2. Pulumi state in S3 on a local AWS emulator.
	emulator := builder.AddContainer("aws-emulator", "floci/floci").
		WithImageTag("latest").
		WithHttpEndpoint(aspire.HttpEndpointTargetPort(4566), aspire.HttpEndpointName("http"))

	viewer("pulumi-viewer-local").
		WithEnvironment("PULUMI_BACKEND_URL", "s3://pulumi-state").
		WithEnvironment("AWS_ENDPOINT_URL", emulator.GetEndpoint("http")).
		WithEnvironment("AWS_ACCESS_KEY_ID", "test").
		WithEnvironment("AWS_SECRET_ACCESS_KEY", "test").
		WaitFor(emulator)

	// 3. A real bucket. Set the parameters in the dashboard or user secrets.
	accessKey := builder.AddParameter("aws-access-key-id", aspire.ParameterSecret(true))
	secretKey := builder.AddParameter("aws-secret-access-key", aspire.ParameterSecret(true))
	sessionToken := builder.AddParameter("aws-session-token", aspire.ParameterSecret(true))

	viewer("pulumi-viewer-dev").
		WithEnvironment("PULUMI_BACKEND_URL", "s3://my-pulumi-state").
		WithEnvironment("AWS_REGION", "us-east-1").
		WithEnvironment("AWS_ACCESS_KEY_ID", accessKey).
		WithEnvironment("AWS_SECRET_ACCESS_KEY", secretKey).
		WithEnvironment("AWS_SESSION_TOKEN", sessionToken)

	app, err := builder.Build()
	if err != nil {
		log.Fatal(aspire.FormatError(err))
	}
	if err := app.Run(); err != nil {
		log.Fatal(aspire.FormatError(err))
	}
}
```

## Write state into the emulator

The `pulumi-viewer-local` resource reads what the Pulumi CLI writes. Point the CLI at the same
emulator, create the bucket once, and deploy a stack:

```sh
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1
aws --endpoint-url http://localhost:4566 s3 mb s3://pulumi-state
pulumi login 's3://pulumi-state?endpoint=localhost:4566&s3ForcePathStyle=true&disableSSL=true'
pulumi stack init dev && pulumi up
```

Use the host port that the Aspire dashboard shows for `aws-emulator` instead of `4566` when Aspire
picks a random port.
