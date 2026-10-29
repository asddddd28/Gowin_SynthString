import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './tests', timeout: 30000, workers: 1,
  reporter: [['list'], ['json', { outputFile: '../reports/performance_ui_tests.json' }]],
  use: { channel: 'msedge', headless: true, viewport: { width: 1440, height: 940 }, baseURL: 'http://127.0.0.1:1421', trace: 'retain-on-failure' },
  webServer: { command: 'npm run dev -- --mode test', url: 'http://127.0.0.1:1421', reuseExistingServer: false },
});
