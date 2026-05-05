import { defineConfig } from 'tsup';

// Bundle the workspace `@xdyb/shared` into the server output so that
// `node server/dist/index.js` runs without needing a built copy of the
// shared package on disk. socket.io / node built-ins remain external —
// they're real npm dependencies resolved from node_modules at runtime.
export default defineConfig({
  entry: ['src/index.ts', 'src/sim.ts'],
  format: ['esm'],
  target: 'node20',
  outDir: 'dist',
  clean: true,
  noExternal: ['@xdyb/shared'],
  splitting: false,
  sourcemap: false,
});
