import { defineConfig } from 'vite';

// Static single-page build. Output goes to dist/ and is synced to S3 by CI.
export default defineConfig({
  base: './',
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
    minify: 'esbuild',
  },
  server: {
    port: 5173,
  },
});
