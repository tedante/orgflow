#!/usr/bin/env node --import tsx
import React, { useCallback, useEffect, useState } from "react";
import { Box, Static, Text, render, useApp, useInput, useStdout } from "ink";
import { PROJECT_ROOT, parseConfigFile, parseTemplateItem } from "./config.js";
import { runScript } from "./runner.js";

// Single action list — no DRY-RUN duplication.
// Every action runs: template pick (optional) → auto-preview (--dry-run)
// → y confirm → real execution. The --dry-run flag stays as the preview
// mechanism, it is just no longer a separate menu item.
const ACTIONS = [
  {
    key: "invite",
    label: "Invite students",
    script: "invite.sh",
    filter: false,
  },
  {
    key: "create",
    label: "Create repos",
    script: "create-repo.sh",
    filter: true,
  },
  {
    key: "clone",
    label: "Clone repos",
    script: "clone-repos.sh",
    filter: true,
  },
];

const OTHER_ITEMS = [
  { key: "refresh", action: "refresh", label: "Refresh status", hint: "R" },
  { key: "auth", action: "auth", label: "Check gh auth", hint: "A" },
  { key: "quit", action: "quit", label: "Quit", hint: "Q" },
];

function actionHint(action, config) {
  if (!config.ok) return "config missing";
  const { org, teamName, users, templates, cloneDir } = config.config;
  if (action.key === "invite")
    return `${users.length} users → team ${teamName || "?"}`;
  if (action.key === "create")
    return `${templates.length} templates × ${users.length} users = ${
      templates.length * users.length
    } repos`;
  if (action.key === "clone")
    return `${templates.length} templates → ${cloneDir || "."}/`;
  return "";
}

function StatusBar({ config, auth }) {
  if (!config.ok) {
    return (
      <Box flexDirection="column">
        <Text color="red" bold>
          Config error
        </Text>
        <Text color="yellow">{config.message}</Text>
        <Text dim>Actions are disabled until the config loads.</Text>
      </Box>
    );
  }
  const { org, teamName, users, reviewers, templates, cloneDir } =
    config.config;
  return (
    <Box flexDirection="column">
      <Text bold>
        Orgflow <Text dim>·</Text> <Text color="cyan">{org || "?"}</Text>{" "}
        <Text dim>/</Text> {teamName || "?"}
      </Text>
      <Text>
        <Text dim>users </Text>
        <Text bold>{users.length}</Text>
        <Text dim> · templates </Text>
        <Text bold>{templates.length}</Text>
        <Text dim> · reviewers </Text>
        <Text bold>{reviewers.length}</Text>
        {cloneDir ? (
          <>
            <Text dim> · dir </Text>
            {cloneDir}
          </>
        ) : null}
      </Text>
      <Text>
        <Text dim>gh </Text>
        <AuthStatus auth={auth} />
      </Text>
    </Box>
  );
}

function AuthStatus({ auth }) {
  if (auth.status === "checking") return <Text dim>checking…</Text>;
  if (auth.status === "not-installed")
    return <Text color="red">not installed — install GitHub CLI</Text>;
  if (auth.status === "error")
    return (
      <Text color="red">
        not authenticated — run <Text bold>gh auth login</Text>
      </Text>
    );
  return auth.adminOrg ? (
    <Text color="green">OK (admin:org)</Text>
  ) : (
    <Text color="yellow">OK — no admin:org scope</Text>
  );
}

function Menu({ config, cursor }) {
  const total = ACTIONS.length + OTHER_ITEMS.length;
  const cursorAction = cursor < ACTIONS.length;
  return (
    <Box flexDirection="column">
      <Box marginTop={1} flexDirection="column">
        {ACTIONS.map((a, i) => (
          <Text
            key={a.key}
            color={i === cursor ? "green" : undefined}
            bold={i === cursor}
            dim={!config.ok}
          >
            {i === cursor ? "▶ " : "  "}
            <Text bold>{i + 1}</Text> {a.label}{" "}
            <Text dim>— {actionHint(a, config)}</Text>
          </Text>
        ))}
        <Box marginTop={1} flexDirection="column">
          {OTHER_ITEMS.map((o, j) => {
            const i = ACTIONS.length + j;
            return (
              <Text key={o.key} color={i === cursor ? "green" : "white"} dim>
                {i === cursor ? "▶ " : "  "}
                {o.label} <Text dim>({o.hint})</Text>
              </Text>
            );
          })}
        </Box>
      </Box>
      <Text dim marginTop={1}>
        ↑↓ or 1–{ACTIONS.length} select · Enter preview · q quit
      </Text>
      <Text dim>Every action shows a preview first. Nothing runs without y.</Text>
    </Box>
  );
}

function TemplatePicker({ title, templates, selected, cursor }) {
  const count = selected.filter(Boolean).length;
  return (
    <Box flexDirection="column">
      <Text bold color="cyan">
        {title}
      </Text>
      <Text dim>
        {count}/{templates.length} selected
      </Text>
      <Box marginTop={1} flexDirection="column">
        {templates.map((t, i) => (
          <Text
            key={t.raw}
            color={i === cursor ? "green" : "white"}
            bold={i === cursor}
          >
            {i === cursor ? "▶ " : "  "}[{selected[i] ? "x" : " "}] {t.name}
            {t.deadline ? <Text dim> | {t.deadline}</Text> : null}
          </Text>
        ))}
      </Box>
      <Text dim marginTop={1}>
        space toggle · a select all/none · Enter preview · esc back
      </Text>
      {count === 0 && (
        <Text color="yellow">Select at least one template</Text>
      )}
    </Box>
  );
}

function PreviewView({ preview }) {
  const { label, summary, lines, running, code } = preview;
  const status = running
    ? "loading preview…"
    : code === 0
      ? `preview ok — ${lines.length} lines`
      : `preview failed (exit ${code})`;
  return (
    <Box flexDirection="column">
      <Text bold>
        Preview <Text dim>·</Text> {label}
      </Text>
      {summary ? <Text dim>{summary}</Text> : null}
      <Text dim>{status} — no changes made</Text>
      <Box marginTop={1} flexDirection="column">
        <Static items={lines}>
          {(line, i) => <Text key={i}>{line}</Text>}
        </Static>
      </Box>
      {!running && code === 0 && (
        <Box marginTop={1} flexDirection="column">
          <Text color="yellow" bold>
            Run for real? This cannot be undone.
          </Text>
          <Text dim>y execute · n back</Text>
        </Box>
      )}
      {!running && code !== 0 && (
        <Text dim marginTop={1}>
          Fix the issue above. Enter to go back.
        </Text>
      )}
    </Box>
  );
}

function RunView({ run }) {
  const { label, lines, running, code, error } = run;
  const status =
    error !== null
      ? `failed: ${error}`
      : running
        ? "running…"
        : code === 0
          ? `done (exit ${code})`
          : `failed (exit ${code}) — see output above`;
  return (
    <Box flexDirection="column">
      <Text bold>
        {label} <Text dim>— {status}</Text>
      </Text>
      <Static items={lines}>
        {(line, i) => (
          <Text key={i} color={error !== null ? "red" : undefined}>
            {line}
          </Text>
        )}
      </Static>
      {!running && (
        <Text dim marginTop={1}>
          Press Enter to return to menu
        </Text>
      )}
    </Box>
  );
}

function App() {
  const { exit } = useApp();
  const { stdout } = useStdout();
  const cols = stdout?.columns ?? 80;
  const frameHeight = Math.max((stdout?.rows ?? 24) - 2, 8);
  const [view, setView] = useState("menu");
  const [cursor, setCursor] = useState(0);
  const [config, setConfig] = useState({ ok: false, message: "loading…" });
  const [auth, setAuth] = useState({ status: "checking" });
  const [pending, setPending] = useState(null);
  const [pendingEnv, setPendingEnv] = useState({});
  const [pendingSummary, setPendingSummary] = useState("");
  const [selected, setSelected] = useState([]);
  const [tplCursor, setTplCursor] = useState(0);
  const [preview, setPreview] = useState(null);
  const [run, setRun] = useState(null);

  const totalItems = ACTIONS.length + OTHER_ITEMS.length;
  const templateItems = config.ok
    ? config.config.templates.map(parseTemplateItem)
    : [];
  const n = templateItems.length;

  const checkAuth = useCallback(async () => {
    setAuth({ status: "checking" });
    const r = await runScript({
      command: "gh",
      args: ["auth", "status", "-h", "github.com"],
    });
    if (r.code === -1 && r.error?.includes("ENOENT")) {
      setAuth({ status: "not-installed" });
      return;
    }
    if (r.code !== 0) {
      setAuth({ status: "error", detail: r.lines?.join("\n") });
      return;
    }
    setAuth({
      status: "ok",
      adminOrg: r.lines.join("\n").includes("admin:org"),
      detail: r.lines.join("\n"),
    });
  }, []);

  const refresh = useCallback(() => {
    setConfig(parseConfigFile());
    checkAuth();
  }, [checkAuth]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const summarizeEnv = useCallback(
    (action, env) => {
      if (!config.ok) return "";
      const picked = env.ORGFLOW_TEMPLATES
        ? env.ORGFLOW_TEMPLATES.split(";").map(
            (raw) => parseTemplateItem(raw).name,
          )
        : config.config.templates.map((t) => parseTemplateItem(t).name);
      const users = config.config.users.length;
      if (action.key === "invite")
        return `${users} users → team ${config.config.teamName}`;
      if (action.key === "create")
        return `${picked.length} templates × ${users} users = ${
          picked.length * users
        } repos (${picked.join(", ")})`;
      return `${picked.join(", ")} → ${config.config.cloneDir || "."}/`;
    },
    [config],
  );

  const startPreview = useCallback(
    async (action, env = {}) => {
      const summary = summarizeEnv(action, env);
      setPending(action);
      setPendingEnv(env);
      setPendingSummary(summary);
      setView("preview");
      setPreview({
        label: action.label,
        summary,
        script: action.script,
        lines: [],
        running: true,
        code: null,
      });
      const r = await runScript({
        command: "bash",
        args: [action.script, "--dry-run"],
        cwd: PROJECT_ROOT,
        env,
        onLine: (line) =>
          setPreview((prev) =>
            prev ? { ...prev, lines: [...prev.lines, line] } : prev,
          ),
      });
      setPreview((prev) =>
        prev ? { ...prev, running: false, code: r.code } : prev,
      );
    },
    [summarizeEnv],
  );

  const startRun = useCallback(async (action, env = {}) => {
    setView("run");
    setRun({
      label: action.label,
      script: action.script,
      lines: [],
      running: true,
      code: null,
      error: null,
    });
    const r = await runScript({
      command: "bash",
      args: [action.script],
      cwd: PROJECT_ROOT,
      env,
      onLine: (line) =>
        setRun((prev) => (prev ? { ...prev, lines: [...prev.lines, line] } : prev)),
    });
    setRun((prev) => ({
      ...prev,
      running: false,
      code: r.code,
      error: r.error ?? null,
    }));
  }, []);

  const enterAction = useCallback(
    (action) => {
      if (!config.ok) return;
      if (action.filter && config.config.templates.length > 1) {
        setPending(action);
        setPendingEnv({});
        setSelected(config.config.templates.map(() => true));
        setTplCursor(0);
        setView("templates");
      } else {
        startPreview(action, {});
      }
    },
    [config, startPreview],
  );

  const onMenuSelect = useCallback(
    (index) => {
      if (index < ACTIONS.length) {
        enterAction(ACTIONS[index]);
        return;
      }
      const other = OTHER_ITEMS[index - ACTIONS.length];
      if (other.action === "quit") exit();
      else if (other.action === "refresh") refresh();
      else if (other.action === "auth") checkAuth();
    },
    [enterAction, exit, refresh, checkAuth],
  );

  useInput((input, key) => {
    if (view === "menu") {
      if (key.upArrow)
        setCursor((c) => (c - 1 + totalItems) % totalItems);
      else if (key.downArrow) setCursor((c) => (c + 1) % totalItems);
      else if (key.return) onMenuSelect(cursor);
      else if (input === "q" || key.escape) exit();
      else if (input === "r") refresh();
      else if (input === "a") checkAuth();
      else {
        const num = parseInt(input, 10);
        if (num >= 1 && num <= ACTIONS.length) onMenuSelect(num - 1);
      }
    } else if (view === "templates") {
      if (key.upArrow) setTplCursor((c) => (c - 1 + n) % n);
      else if (key.downArrow) setTplCursor((c) => (c + 1) % n);
      else if (input === " ") {
        setSelected((prev) => prev.map((v, i) => (i === tplCursor ? !v : v)));
      } else if (input === "a") {
        setSelected((prev) =>
          prev.every(Boolean) ? prev.map(() => false) : prev.map(() => true),
        );
      } else if (key.return) {
        if (!selected.some(Boolean)) return;
        const env = {
          ORGFLOW_TEMPLATES: templateItems
            .filter((_, i) => selected[i])
            .map((t) => t.raw)
            .join(";"),
        };
        startPreview(pending, env);
      } else if (key.escape) {
        setView("menu");
      }
    } else if (view === "preview") {
      if (preview?.running) return;
      if (preview?.code === 0) {
        if (input === "y") startRun(pending, pendingEnv);
        else if (input === "n" || key.escape) setView("menu");
      } else if (preview && !preview.running) {
        if (key.return || key.escape) setView("menu");
      }
    } else if (view === "run" && !run?.running && key.return) {
      setView("menu");
    }
  });

  const centered = view === "menu" || view === "templates";

  return (
    <Box
      width={cols}
      minHeight={frameHeight}
      borderStyle="round"
      borderColor="cyan"
      paddingX={3}
      paddingY={1}
      flexDirection="column"
    >
      {(view === "menu" || view === "templates") && (
        <StatusBar config={config} auth={auth} />
      )}
      {centered ? (
        <Box flexGrow={1} alignItems="center" justifyContent="center">
          <Box flexDirection="column">
            {view === "menu" && <Menu config={config} cursor={cursor} />}
            {view === "templates" && config.ok && (
              <TemplatePicker
                title={`Select template(s) — ${pending?.label}`}
                templates={templateItems}
                selected={selected}
                cursor={tplCursor}
              />
            )}
          </Box>
        </Box>
      ) : (
        <>
          {view === "preview" && preview && <PreviewView preview={preview} />}
          {view === "run" && run && <RunView run={run} />}
        </>
      )}
    </Box>
  );
}

render(<App />);
