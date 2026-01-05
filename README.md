# docker-enforce

> Enforces Docker-first development policy by intercepting package manager and runtime commands on the host.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://claude.ai/claude-code)

## Why Docker-Enforce?

When developing with Docker, it's easy to accidentally run `npm install` or other commands on your host machine instead of inside the container. This leads to:

- **Native module mismatches** - Modules compiled on macOS won't work in Linux containers
- **Version inconsistencies** - Host Node.js version differs from container
- **Missing dependencies** - Dependencies installed on host aren't in the container
- **CI/CD failures** - Works locally but fails in Docker-based CI

`docker-enforce` prevents these issues by intercepting commands and ensuring they run inside Docker.

## Installation

### As a Claude Code Skill (Recommended)

```bash
# Clone to your Claude Code skills directory
git clone https://github.com/claude-code-skills/docker-enforce.git ~/.claude/skills/docker-enforce

# Make the hook executable
chmod +x ~/.claude/skills/docker-enforce/hooks/pre-command.sh
```

### Via npm (for CLI usage)

```bash
npm install -g docker-enforce
```

## Quick Start

1. **Configure your project** - Create `.claude/docker-config.json`:

```json
{
  "containerName": "myproject-dev-1",
  "enforcement": "block"
}
```

2. **Start your Docker container**:

```bash
docker compose up -d
```

3. **Try running a command** - It will be intercepted:

```bash
$ npm install express

ERROR: Docker-first policy violation detected!

Command: npm install express
Reason:  Package manager commands must run inside Docker

Suggested command:
  docker exec myproject-dev-1 npm install express
```

## Configuration

Create `.claude/docker-config.json` in your project root:

```json
{
  "containerName": "myproject-dev-1",
  "enforcement": "block",
  "allowedHostCommands": [
    "npm run lint",
    "npm run format"
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

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `containerName` | string | required | Name of your Docker container |
| `enforcement` | string | `"block"` | `"block"`, `"warn"`, `"transform"`, or `"disabled"` |
| `allowedHostCommands` | array | `[]` | Commands that can run on host |
| `interceptPatterns` | object | all `true` | Which tools to intercept |

### Enforcement Modes

| Mode | Behavior |
|------|----------|
| `block` | Stop with error message and docker exec suggestion |
| `warn` | Show warning but allow command to proceed |
| `transform` | Automatically run command inside container |
| `disabled` | Skip enforcement for this project |

## Intercepted Commands

By default, these commands are intercepted:

- `npm install`, `npm ci`, `npm run`, `npm test`, `npm exec`
- `npx <anything>`
- `yarn add`, `yarn install`, `yarn run`
- `pnpm add`, `pnpm install`, `pnpm run`
- `node <script>`
- `tsx <script>`
- `bun run`, `bun install`, `bun add`

## CLI Usage

```bash
# Check if a command would be blocked
docker-enforce check "npm install express"

# Validate container is running
docker-enforce validate

# Get the docker exec version of a command
docker-enforce transform "npm install express"
# Output: docker exec myproject-dev-1 npm install express
```

## Integration with Claude Code

When used as a Claude Code skill, `docker-enforce` automatically:

1. Activates when you use trigger phrases like "npm install", "run the build"
2. Reads your project's `.claude/docker-config.json`
3. Validates the container is running
4. Blocks or transforms commands based on your enforcement mode

### Related Skills

For complete Docker development support, use with:

| Skill | Purpose |
|-------|---------|
| **docker** | Documentation and best practices for Docker-first development |
| **docker-guard** | Prevents hangs when Docker daemon is unresponsive |
| **docker-optimizer** | Analyzes Dockerfiles for optimization opportunities |

## Examples

### Block Mode (Default)

```
$ npm install lodash

ERROR: Docker-first policy violation detected!

Command: npm install lodash
Reason:  Package manager commands must run inside Docker

Suggested command:
  docker exec myproject-dev-1 npm install lodash

To allow this command on host, add to .claude/docker-config.json:
  "allowedHostCommands": ["npm install lodash"]
```

### Warn Mode

```
$ npm install lodash

WARNING: Running package manager on host instead of Docker
Recommended: docker exec myproject-dev-1 npm install lodash
Proceeding anyway...
```

### Transform Mode

```
$ npm install lodash
Transforming to: docker exec myproject-dev-1 npm install lodash

added 1 package in 1s
```

## Allowing Host Commands

Some commands are safe to run on the host (linting, formatting). Add them to your config:

```json
{
  "allowedHostCommands": [
    "npm run lint",
    "npm run lint:fix",
    "npm run format",
    "npm run typecheck"
  ]
}
```

## Troubleshooting

### Container not running

```
ERROR: Container 'myproject-dev-1' is not running
Start it with: docker compose up -d
```

**Solution**: Start your container with `docker compose up -d`

### No container configured

```
WARNING: No containerName configured in .claude/docker-config.json
```

**Solution**: Create `.claude/docker-config.json` with your container name

### Want to disable temporarily

Set enforcement to `disabled`:

```json
{
  "enforcement": "disabled"
}
```

Or use an allowed command pattern.

## Project Structure

```
docker-enforce/
├── SKILL.md           # Claude Code skill definition
├── README.md          # This file
├── package.json       # npm package configuration
├── LICENSE            # MIT License
├── hooks/
│   └── pre-command.sh # Bash hook for command interception
└── scripts/
    └── enforce.ts     # TypeScript implementation
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built for the [Claude Code](https://claude.ai/claude-code) ecosystem
- Inspired by the need for consistent Docker-first development practices
