#!/usr/bin/env node
// Prints one free TCP port on 127.0.0.1 to stdout. Used by the pre-push
// website-CI gate so it never collides with a long-lived `astro dev` server
// a developer happens to have running — it always spins up its own isolated
// preview server instead of hardcoding port 4321 (see playwright.config.ts).
import { createServer } from 'node:net';

const server = createServer();
server.listen(0, '127.0.0.1', () => {
  const { port } = server.address();
  server.close(() => {
    process.stdout.write(String(port));
  });
});
server.on('error', (err) => {
  console.error(`find-free-port: ${err.message}`);
  process.exit(1);
});
