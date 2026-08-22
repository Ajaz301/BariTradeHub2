import { defineConfig } from 'vite';
import { copyFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';

function copyStaticFiles() {
  return {
    name: 'copy-static-files',
    closeBundle() {
      const outDir = 'dist';
      if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });
      // Copy _redirects so the /admin route works in production
      if (existsSync('_redirects')) copyFileSync('_redirects', join(outDir, '_redirects'));
    },
  };
}

export default defineConfig({
  server: {
    middlewareMode: false,
  },
  build: {
    rollupOptions: {
      input: {
        main: 'index.html',
        admin: 'admin.html',
      },
    },
  },
  plugins: [copyStaticFiles()],
});
