#!/usr/bin/env npx tsx
/**
 * Docker Enforce - TypeScript implementation
 * Enforces Docker-first development policy
 */

import { execSync } from 'child_process';
import { existsSync, readFileSync } from 'fs';
import { join } from 'path';

interface DockerConfig {
  containerName?: string;
  enforcement?: 'block' | 'warn' | 'transform' | 'disabled';
  allowedHostCommands?: string[];
  interceptPatterns?: {
    npm?: boolean;
    npx?: boolean;
    yarn?: boolean;
    pnpm?: boolean;
    node?: boolean;
    tsx?: boolean;
    bun?: boolean;
  };
}

const DEFAULT_CONFIG: DockerConfig = {
  enforcement: 'block',
  allowedHostCommands: [],
  interceptPatterns: {
    npm: true,
    npx: true,
    yarn: true,
    pnpm: true,
    node: true,
    tsx: true,
    bun: true,
  },
};

const INTERCEPT_PATTERNS: Record<string, RegExp> = {
  npm: /^npm\s+(install|ci|run|test|exec|start|build)/,
  npx: /^npx\s+/,
  yarn: /^yarn\s+(add|install|run|start|build)/,
  pnpm: /^pnpm\s+(add|install|run|start|build)/,
  node: /^node\s+/,
  tsx: /^tsx\s+/,
  bun: /^bun\s+(run|install|add)/,
};

// ANSI color codes
const colors = {
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  green: '\x1b[32m',
  blue: '\x1b[34m',
  reset: '\x1b[0m',
};

function loadConfig(projectPath: string = process.cwd()): DockerConfig {
  const configPath = join(projectPath, '.claude', 'docker-config.json');

  if (!existsSync(configPath)) {
    return DEFAULT_CONFIG;
  }

  try {
    const content = readFileSync(configPath, 'utf-8');
    const config = JSON.parse(content) as Partial<DockerConfig>;
    return { ...DEFAULT_CONFIG, ...config };
  } catch {
    console.error(`${colors.yellow}Warning: Could not parse ${configPath}${colors.reset}`);
    return DEFAULT_CONFIG;
  }
}

function shouldIntercept(command: string, config: DockerConfig): boolean {
  const patterns = config.interceptPatterns ?? DEFAULT_CONFIG.interceptPatterns!;

  for (const [tool, enabled] of Object.entries(patterns)) {
    if (enabled && INTERCEPT_PATTERNS[tool]?.test(command)) {
      return true;
    }
  }

  return false;
}

function isAllowed(command: string, config: DockerConfig): boolean {
  const allowed = config.allowedHostCommands ?? [];

  for (const allowedCmd of allowed) {
    if (command === allowedCmd || command.startsWith(allowedCmd + ' ')) {
      return true;
    }
  }

  return false;
}

function isContainerRunning(containerName: string): boolean {
  try {
    const output = execSync(`docker ps --format '{{.Names}}'`, {
      encoding: 'utf-8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return output.split('\n').includes(containerName);
  } catch {
    return false;
  }
}

function showBlockMessage(command: string, containerName?: string): void {
  console.error(`${colors.red}ERROR: Docker-first policy violation detected!${colors.reset}`);
  console.error('');
  console.error(`Command: ${colors.blue}${command}${colors.reset}`);
  console.error('Reason:  Package manager commands must run inside Docker');
  console.error('');

  if (containerName) {
    console.error('Suggested command:');
    console.error(`  ${colors.green}docker exec ${containerName} ${command}${colors.reset}`);
  } else {
    console.error('Configure containerName in .claude/docker-config.json first');
  }

  console.error('');
  console.error('To allow this command on host, add to .claude/docker-config.json:');
  console.error(`  "allowedHostCommands": ["${command}"]`);
}

function showWarning(command: string, containerName?: string): void {
  console.error(
    `${colors.yellow}WARNING: Running package manager on host instead of Docker${colors.reset}`
  );
  if (containerName) {
    console.error(
      `Recommended: ${colors.green}docker exec ${containerName} ${command}${colors.reset}`
    );
  }
  console.error('Proceeding anyway...');
}

interface EnforceResult {
  action: 'allow' | 'block' | 'warn' | 'transform';
  message?: string;
  transformedCommand?: string;
}

export function enforce(command: string, projectPath?: string): EnforceResult {
  const config = loadConfig(projectPath);

  // Check if enforcement is disabled
  if (config.enforcement === 'disabled') {
    return { action: 'allow' };
  }

  // Check if command should be intercepted
  if (!shouldIntercept(command, config)) {
    return { action: 'allow' };
  }

  // Check if command is explicitly allowed
  if (isAllowed(command, config)) {
    return { action: 'allow' };
  }

  const containerName = config.containerName;

  // Apply enforcement policy
  switch (config.enforcement) {
    case 'block':
      showBlockMessage(command, containerName);
      return { action: 'block', message: 'Docker-first policy violation' };

    case 'warn':
      showWarning(command, containerName);
      return { action: 'warn' };

    case 'transform':
      if (!containerName) {
        console.error(`${colors.red}ERROR: Cannot transform - no containerName configured${colors.reset}`);
        return { action: 'block', message: 'No container configured' };
      }
      if (!isContainerRunning(containerName)) {
        console.error(`${colors.red}ERROR: Container '${containerName}' is not running${colors.reset}`);
        console.error(`Start it with: ${colors.green}docker compose up -d${colors.reset}`);
        return { action: 'block', message: 'Container not running' };
      }
      const transformedCommand = `docker exec ${containerName} ${command}`;
      console.error(`${colors.blue}Transforming to:${colors.reset} ${transformedCommand}`);
      return { action: 'transform', transformedCommand };

    default:
      return { action: 'allow' };
  }
}

// CLI interface
function main(): void {
  const args = process.argv.slice(2);
  const action = args[0];
  const command = args.slice(1).join(' ');

  switch (action) {
    case 'check': {
      if (!command) {
        console.error('Usage: enforce.ts check <command>');
        process.exit(1);
      }
      const config = loadConfig();
      if (shouldIntercept(command, config) && !isAllowed(command, config)) {
        console.log(`WOULD_BLOCK: ${command}`);
        process.exit(1);
      } else {
        console.log(`ALLOWED: ${command}`);
        process.exit(0);
      }
      break;
    }

    case 'validate': {
      const config = loadConfig();
      if (!config.containerName) {
        console.log('ERROR: No container configured');
        process.exit(1);
      }
      if (isContainerRunning(config.containerName)) {
        console.log(`OK: Container '${config.containerName}' is running`);
        process.exit(0);
      } else {
        console.log(`ERROR: Container '${config.containerName}' is not running`);
        process.exit(1);
      }
      break;
    }

    case 'transform': {
      if (!command) {
        console.error('Usage: enforce.ts transform <command>');
        process.exit(1);
      }
      const config = loadConfig();
      if (config.containerName) {
        console.log(`docker exec ${config.containerName} ${command}`);
      } else {
        console.error('ERROR: No container configured');
        process.exit(1);
      }
      break;
    }

    case 'enforce':
    default: {
      const cmd = action === 'enforce' ? command : [action, command].filter(Boolean).join(' ');
      if (!cmd) {
        console.error('Usage: enforce.ts [enforce] <command>');
        process.exit(1);
      }
      const result = enforce(cmd);
      if (result.action === 'block') {
        process.exit(1);
      }
      break;
    }
  }
}

// Run if executed directly
main();
