import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export const PROJECT_ROOT = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '..',
);

export function configPath() {
  return process.env.CONFIG_FILE ?? path.join(PROJECT_ROOT, 'orgflow.conf');
}

const SCALAR_RE = /^([A-Z_]+)="([^"]*)"/gm;
const ARRAY_RE = /^([A-Z_]+)=\(\s*\)|^([A-Z_]+)=\(([\s\S]*?)\)/gm;
const ARRAY_ITEM_RE = /"([^"]*)"|(\S+)/g;

const splitList = (s) => (s ?? '').split(/\s+/).filter(Boolean);

export function parseConfig(source) {
  const scalar = {};
  let m;
  SCALAR_RE.lastIndex = 0;
  while ((m = SCALAR_RE.exec(source)) !== null) {
    scalar[m[1]] = m[2].trim();
  }

  const arrays = {};
  ARRAY_RE.lastIndex = 0;
  while ((m = ARRAY_RE.exec(source)) !== null) {
    const name = m[2] ?? m[1];
    const body = m[3] ?? '';
    const items = [];
    let it;
    ARRAY_ITEM_RE.lastIndex = 0;
    while ((it = ARRAY_ITEM_RE.exec(body)) !== null) {
      items.push(it[1] ?? it[2]);
    }
    arrays[name] = items;
  }

  return {
    org: scalar.ORG ?? '',
    teamName: scalar.TEAM_NAME ?? '',
    cloneDir: scalar.CLONE_DIR ?? '',
    users: splitList(scalar.USERS),
    reviewers: splitList(scalar.REVIEWERS),
    templates: arrays.TEMPLATES ?? [],
  };
}

export function cleanRepoName(templateRepo) {
  const base = templateRepo.split('/')[1] ?? templateRepo;
  return base
    .replace(/(^|[-_])template([-_]|$)/g, '$1')
    .replace(/^[-_]/, '')
    .replace(/[-_]$/, '');
}

export function parseTemplateItem(item) {
  const [repo, deadline] = item.split('|');
  return {
    raw: item,
    repo: repo ?? item,
    deadline: deadline?.trim() ?? '',
    name: cleanRepoName(repo ?? item),
  };
}

export function parseConfigFile() {
  const p = configPath();
  try {
    const source = readFileSync(p, 'utf8');
    return { ok: true, path: p, config: parseConfig(source) };
  } catch (err) {
    return {
      ok: false,
      path: p,
      message:
        err.code === 'ENOENT'
          ? `Config not found: ${p} — copy orgflow.conf.example to orgflow.conf`
          : err.message,
    };
  }
}
