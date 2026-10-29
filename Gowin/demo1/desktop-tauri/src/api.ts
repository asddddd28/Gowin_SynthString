import { invoke, isTauri } from '@tauri-apps/api/core';
import { open, save } from '@tauri-apps/plugin-dialog';

declare global { interface Window { __STUDIO_TEST__?: (method: string, params: unknown) => Promise<unknown> } }

export async function request<T = void>(method: string, params: Record<string, unknown> = {}): Promise<T> {
  // The harness calls the real Rust engine. Simulated serial IO is test-only.
  if (import.meta.env.MODE === 'test' && window.__STUDIO_TEST__) return await window.__STUDIO_TEST__(method, params) as T;
  if (!isTauri()) throw new Error('请通过 TangSynthStudio.exe 或 npm run tauri dev 打开；浏览器预览无法访问硬件后台。');
  return invoke<T>('studio_request', { method, params });
}

export async function chooseFile(title: string, extensions: string[], writing = false): Promise<string | null> {
  if (!isTauri()) throw new Error('文件对话框需要在 Tauri 桌面窗口中使用。');
  await request('release_all');
  const options = { title, filters: [{ name: title, extensions }] };
  if (writing) return save(options);
  return open({ ...options, multiple: false, directory: false }) as Promise<string | null>;
}
