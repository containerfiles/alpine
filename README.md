# alpine

Minimal Alpine Linux base image for Apple's native [Containerization](https://github.com/apple/containerization) framework.

## Prerequisites

- macOS 26+ (Tahoe)
- Apple Silicon
- [container](https://github.com/apple/container) CLI installed
- [container-cast](https://github.com/containerfiles/container-cast) (for standalone binaries)

## Usage

### Run as container

```bash
make build          # Build the image
make run            # Spawn ephemeral shell at alpine.lab
```

### Cast as standalone binary

```bash
make install        # Build, cast, and install to /usr/local/bin
alpine              # Launch interactive shell
alpine <command>    # Run a single command
```

### All targets

```
make status      Show builder, DNS, images, and containers
make build       Build the container image
make cast        Cast into a standalone binary
make install     Cast and install to /usr/local/bin
make uninstall   Remove from /usr/local/bin
make run         Run the container
make clean       Remove image and prune unused resources
make dns         Configure .lab DNS domain (run once, needs sudo)
make nuke        Kill and restart the builder (fixes hangs)
make help        Show all targets
```

## What's Inside

- Alpine Linux (latest)
- BusyBox utilities
- ash shell

Smallest footprint base image. Use as a foundation for containers needing minimal dependencies.

## License

MIT
