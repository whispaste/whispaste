// Vitest global setup.
//
// jsdom does not implement the Web Storage API (localStorage / sessionStorage)
// unless its document is constructed with a non-opaque URL, and Vitest 4's
// jsdom environment leaves both undefined. Tests that touch storage (e.g. the
// changelog hydrator cache) therefore crash in `beforeEach` with
// "Cannot read properties of undefined (reading 'clear')".
//
// Provide a minimal, spec-shaped in-memory Storage so those tests run
// deterministically. Guarded by an existence check, so a real implementation
// (browser, or a future jsdom that ships Storage) is never overwritten.

class MemoryStorage {
  private store = new Map<string, string>();

  get length(): number {
    return this.store.size;
  }

  clear(): void {
    this.store.clear();
  }

  getItem(key: string): string | null {
    return this.store.has(key) ? (this.store.get(key) as string) : null;
  }

  key(index: number): string | null {
    return Array.from(this.store.keys())[index] ?? null;
  }

  removeItem(key: string): void {
    this.store.delete(key);
  }

  setItem(key: string, value: string): void {
    this.store.set(key, String(value));
  }
}

function installStorage(name: 'localStorage' | 'sessionStorage'): void {
  const g = globalThis as Record<string, unknown>;
  if (typeof g[name] === 'undefined') {
    Object.defineProperty(globalThis, name, {
      value: new MemoryStorage() as unknown as Storage,
      writable: true,
      configurable: true,
    });
  }
}

installStorage('localStorage');
installStorage('sessionStorage');
