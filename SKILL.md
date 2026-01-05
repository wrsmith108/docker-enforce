# Docker Enforce Skill

Automatically enforces Docker-first development policy by intercepting package manager and runtime commands on the host.

## Metadata

```yaml
name: docker-enforce
version: 1.0.0
description: Enforces Docker-first development by intercepting host commands
author: Community
license: MIT
triggers:
  - "npm install"
  - "npm ci"
  - "npx"
  - "yarn add"
  - "pnpm install"
  - "node script"
  - "bun run"
dependencies:
  - docker (skill) - complementary documentation
  - docker-guard (hook) - complementary daemon health
tools:
  - Docker Desktop or Docker Engine
  - Bash shell
```

## Purpose

Prevents accidental execution of package manager commands on the host machine instead of inside Docker containers. This skill:

1. **Intercepts** commands like `npm install`, `npx`, `yarn`, `pnpm`, `node`, `tsx`, `bun`
2. **Validates** that the target Docker container is running
3. **Enforces** policy by blocking, warning, or auto-transforming commands

## Enforcement Modes

| Mode | Behavior |
|------|----------|
| `block` | Stop execution with error message and suggestion |
| `warn` | Display warning but allow command to proceed |
| `transform` | Auto-prefix command with `docker exec <container>` |

## Configuration

Create `.claude/docker-config.json` in your project root:

```json
{
  "containerName": "myproject-dev-1",
  "enforcement": "block",
  "allowedHostCommands": [
    "npm run lint",
    "npm run format",
    "npm run typecheck"
  ],
  "interceptPatterns": {
    "npm": true,
    "npx": true,
    "yarn": true,
    "pnpm": true,
    "node": true,
    "tsx": true,
    "bun": true
  }
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `containerName` | string | - | Docker container name (required) |
| `enforcement` | string | `block` | Enforcement mode: block, warn, transform |
| `allowedHostCommands` | string[] | `[]` | Commands allowed on host |
| `interceptPatterns` | object | all true | Which package managers to intercept |

## Usage

### Automatic (via Claude Code hooks)

The skill automatically intercepts commands when configured. No manual invocation needed.

### Manual Check

```bash
# Check if a command would be blocked
~/.claude/skills/docker-enforce/scripts/enforce.sh check "npm install express"

# Validate container is running
~/.claude/skills/docker-enforce/scripts/enforce.sh validate

# Get transformed command
~/.claude/skills/docker-enforce/scripts/enforce.sh transform "npm install express"
```

## Examples

### Blocked Command

```
$ npm install express

ERROR: Docker-first policy violation detected!

Command: npm install express
Reason:  Package manager commands must run inside Docker

Suggested command:
  docker exec myproject-dev-1 npm install express

To allow this command on host, add to .claude/docker-config.json:
  "allowedHostCommands": ["npm install express"]
```

### Warning Mode

```
$ npm install express

WARNING: Running package manager on host instead of Docker
Recommended: docker exec myproject-dev-1 npm install express
Proceeding anyway...
```

### Transform Mode

```
$ npm install express
Transforming to: docker exec myproject-dev-1 npm install express
...
added 1 package in 2s
```

## Integration with Other Skills

### docker (documentation skill)

The `docker` skill provides comprehensive documentation for Docker-first development. `docker-enforce` provides the automated enforcement of those policies.

```
docker skill      -> Documents the "why" and "how"
docker-enforce    -> Enforces the "must"
```

### docker-guard (daemon health hook)

The `docker-guard` hook ensures Docker daemon is responsive before commands run. `docker-enforce` handles policy enforcement for package managers.

```
docker-guard      -> "Is Docker daemon healthy?"
docker-enforce    -> "Should this command run in Docker?"
```

### Recommended Setup

Enable all three for complete Docker development support:

```
~/.claude/skills/
├── docker/           # Documentation
├── docker-enforce/   # Policy enforcement (this skill)
└── docker-guard/     # Daemon health (if using hooks)
```

## Troubleshooting

### Command blocked but container not running

```
ERROR: Container 'myproject-dev-1' is not running
Start it with: docker compose up -d
```

### Want to allow specific host commands

Add to `.claude/docker-config.json`:

```json
{
  "allowedHostCommands": [
    "npm run lint",
    "npm run format"
  ]
}
```

### Disable for specific project

Create `.claude/docker-config.json` with:

```json
{
  "enforcement": "disabled"
}
```

## Related Skills

- **docker** - Docker-first development documentation
- **docker-optimizer** - Dockerfile optimization analysis
- **docker-guard** - Docker daemon health monitoring

## License

MIT License - see LICENSE file
