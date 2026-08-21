#!/usr/bin/env node --import tsx
import React, { useCallback, useEffect, useState } from "react";
import { Box, Static, Text, render, useApp, useInput } from "ink";
import { PROJECT_ROOT, parseConfigFile, parseTemplateItem } from "./config.js";
import { runScript } from "./runner.js";

const RUN_ITEMS = [
  {
    section: "DRY-RUN",
    label: "Invite students",
    desc: "preview invitations — no changes",
    script: "invite.sh",
    args: ["--dry-run"],
    real: false,
    filter: false,
  },
  {
    section: "DRY-RUN",
    label: "Create repos",
    desc: "preview repo plan — no changes",
    script: "create-repo.sh",
    args: ["--dry-run"],
    real: false,
    filter: true,
  },
  {
    section: "DRY-RUN",
    label: "Clone repos",
    desc: "preview clone plan — no changes",
    script: "clone-repos.sh",
    args: ["--dry-run"],
    real: false,
    filter: true,
  },
  {
    section: "EXECUTION",
    label: "Invite students",
    desc: "send real org invitations",
    script: "invite.sh",
    args: [],
    real: true,
    filter: false,
  },
  {
    section: "EXECUTION",
    label: "Create repos",
    desc: "create real repos + feedback PRs",
    script: "create-repo.sh",
    args: [],
    real: true,
    filter: true,
  },
  {
    section: "EXECUTION",
    label: "Clone repos",
    desc: "clone real cohort repos",
    script: "clone-repos.sh",
    args: [],
    real: true,
    filter: true,
  },
];

const MENU_ITEMS = [
  ...RUN_ITEMS.map((item, i) => ({ ...item, key: `run-${i}`, action: "run" })),
  { key: "refresh", action: "refresh", label: "Refresh status", section: "OTHER" },
  { key: "auth", action: "auth", label: "Check gh auth", section: "OTHER" },
  { key: "quit", action: "quit", label: "Quit", section: "OTHER" },
];

function StatusBar({ config, auth }) {
  if (!config.ok) {
    return <Text color="yellow">Config: {config.message}</Text>;
  }
  const { org, teamName, users, templates, cloneDir } = config.config;
  return (
    <Box flexDirection="column">
      <Text>
        Config: org=<Text bold>{org || "?"}</Text> team=
        <Text bold>{teamName || "?"}</Text> users=
        <Text bold>{users.length}</Text> templates=
        <Text bold>{templates.length}</Text>
        {cloneDir ? ` cloneDir=${cloneDir}` : ""}
      </Text>
      <Text>
        gh: <AuthStatus auth={auth} />
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
    <Text color="yellow">
      OK — but no admin:org scope, refresh with gh auth refresh -h github.com -s
      admin:org
    </Text>
  );
}

function Menu({ items, cursor }) {
  let lastSection = null;
  return (
    <Box flexDirection="column">
      <Text bold color="cyan">
        Orgflow TUI
      </Text>
      <Box marginTop={1} flexDirection="column">
        {items.map((item, i) => {
          const header =
            item.section && item.section !== lastSection ? (
              <Text bold color={item.section === "EXECUTION" ? "yellow" : "magenta"}>
                {item.section === "EXECUTION"
                  ? "▶ EXECUTION (real GitHub changes)"
                  : item.section === "DRY-RUN"
                    ? "▶ DRY-RUN (preview only, no changes)"
                    : "▶ OTHER"}
              </Text>
            ) : null;
          lastSection = item.section;
          return (
            <Box key={item.key} flexDirection="column">
              {header}
              <Text
                color={i === cursor ? "green" : "white"}
                bold={i === cursor}
              >
                {i === cursor ? "  ▶ " : "    "}
                {item.label}
                {item.desc ? <Text dim> — {item.desc}</Text> : null}
              </Text>
            </Box>
          );
        })}
      </Box>
      <Text dim marginTop={1}>
        ↑↓ navigate · Enter select · q quit
      </Text>
      <Text dim>
        DRY-RUN prints a plan and makes no GitHub changes. EXECUTION makes real
        changes and asks for confirmation first.
      </Text>
    </Box>
  );
}

function RunView({ run }) {
  const { script, args, running, code, error } = run;
  const status =
    run.error !== null
      ? `failed: ${run.error}`
      : running
        ? "running…"
        : code === 0
          ? `exited ${code}`
          : `exited ${code} — see output above`;
  return (
    <Box flexDirection="column">
      <Box paddingX={1} borderStyle="round">
        <Text bold>
          {script} {args.join(" ")}
        </Text>
        <Text dim> — {status}</Text>
      </Box>
      <Static items={run.lines}>
        {(line, i) => (
          <Text key={i} color={run.error !== null ? "red" : undefined}>
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

function TemplatePicker({ title, templates, selected, cursor }) {
  return (
    <Box flexDirection="column">
      <Text bold color="cyan">
        {title}
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
        space toggle · Enter proceed · esc back
      </Text>
      {selected.every((s) => !s) && (
        <Text color="yellow">Select at least one template</Text>
      )}
    </Box>
  );
}

function App() {
  const { exit } = useApp();
  const [view, setView] = useState("menu");
  const [cursor, setCursor] = useState(0);
  const [config, setConfig] = useState({ ok: false, message: "loading…" });
  const [auth, setAuth] = useState({ status: "checking" });
  const [pending, setPending] = useState(null);
  const [pendingEnv, setPendingEnv] = useState({});
  const [selected, setSelected] = useState([]);
  const [tplCursor, setTplCursor] = useState(0);
  const [run, setRun] = useState(null);

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

  const startRun = useCallback(async (item, env = {}) => {
    setView("run");
    setRun({
      script: item.script,
      args: item.args,
      lines: [],
      running: true,
      code: null,
      error: null,
    });
    const r = await runScript({
      command: "bash",
      args: [item.script, ...item.args],
      cwd: PROJECT_ROOT,
      env,
      onLine: (line) =>
        setRun((prev) => ({ ...prev, lines: [...prev.lines, line] })),
    });
    setRun((prev) => ({
      ...prev,
      running: false,
      code: r.code,
      error: r.error ?? null,
    }));
  }, []);

  const onEnter = useCallback(() => {
    const item = MENU_ITEMS[cursor];
    switch (item.action) {
      case "quit":
        exit();
        break;
      case "refresh":
        refresh();
        break;
      case "auth":
        checkAuth();
        break;
      case "run":
        if (item.filter && config.ok && config.config.templates.length > 1) {
          setPending(item);
          setPendingEnv({});
          setSelected(config.config.templates.map(() => false));
          setTplCursor(0);
          setView("templates");
        } else if (item.real) {
          setPending(item);
          setPendingEnv({});
          setView("confirm");
        } else {
          startRun(item);
        }
        break;
    }
  }, [cursor, exit, refresh, checkAuth, startRun, config]);

  useInput((input, key) => {
    if (view === "menu") {
      if (key.upArrow)
        setCursor((c) => (c - 1 + MENU_ITEMS.length) % MENU_ITEMS.length);
      else if (key.downArrow) setCursor((c) => (c + 1) % MENU_ITEMS.length);
      else if (key.return) onEnter();
      else if (input === "q" || key.escape) exit();
    } else if (view === "templates") {
      if (key.upArrow) setTplCursor((c) => (c - 1 + n) % n);
      else if (key.downArrow) setTplCursor((c) => (c + 1) % n);
      else if (input === " ") {
        setSelected((prev) => prev.map((v, i) => (i === tplCursor ? !v : v)));
      } else if (key.return) {
        if (!selected.some(Boolean)) return;
        const env = {
          ORGFLOW_TEMPLATES: templateItems
            .filter((_, i) => selected[i])
            .map((t) => t.raw)
            .join(";"),
        };
        setPendingEnv(env);
        if (pending.real) setView("confirm");
        else startRun(pending, env);
      } else if (key.escape) {
        setView("menu");
      }
    } else if (view === "confirm") {
      if (input === "y") {
        startRun(pending, pendingEnv);
      } else if (input === "n" || key.escape) {
        setView("menu");
      }
    } else if (view === "run" && !run?.running && key.return) {
      setView("menu");
    }
  });

  return (
    <Box padding={1}>
      {view === "menu" && (
        <Box flexDirection="column">
          <StatusBar config={config} auth={auth} />
          <Box marginTop={1} />
          <Menu items={MENU_ITEMS} cursor={cursor} />
        </Box>
      )}
      {view === "templates" && config.ok && (
        <TemplatePicker
          title={`Select template(s) — ${pending?.label}`}
          templates={templateItems}
          selected={selected}
          cursor={tplCursor}
        />
      )}
      {view === "confirm" && (
        <Box flexDirection="column">
          <Text color="yellow" bold>
            ⚠️ Run real GitHub API mutations — {pending?.label}?
          </Text>
          <Text dim>
            This creates/changes org resources and cannot be undone. y confirm ·
            n back
          </Text>
        </Box>
      )}
      {view === "run" && run && <RunView run={run} />}
    </Box>
  );
}

render(<App />);
