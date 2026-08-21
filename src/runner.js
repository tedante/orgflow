import { spawn } from 'node:child_process';

export function runScript({ command = 'bash', args = [], cwd, env = {}, onLine }) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(command, args, { cwd, env: { ...process.env, ...env } });
    } catch (err) {
      resolve({ code: -1, error: err.message, lines: [] });
      return;
    }

    const lines = [];
    let buf = '';
    const onData = (data) => {
      buf += String(data);
      let idx;
      while ((idx = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, idx);
        lines.push(line);
        onLine?.(line);
        buf = buf.slice(idx + 1);
      }
    };

    child.stdout.on('data', onData);
    child.stderr.on('data', onData);
    child.on('error', (err) => resolve({ code: -1, error: err.message, lines }));
    child.on('close', (code) => {
      if (buf) {
        lines.push(buf);
        onLine?.(buf);
      }
      resolve({ code, lines });
    });
  });
}
