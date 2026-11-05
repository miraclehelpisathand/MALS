// Isolated cache for the optional browser test; never disturb the normal preview.
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  cacheDir: join(tmpdir(), 'mals-task5-vite-cache'),
  optimizeDeps: { include: ['react', 'react-dom/client', 'pdf-lib', 'pdfjs-dist', '@pdf-lib/fontkit'] },
  server: { host: '0.0.0.0', allowedHosts: ['.e2b.app'] },
});
