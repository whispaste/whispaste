import { isRetryLater } from './retry-later';

/** Which text the contact widget shows for a refused POST /v1/contact; the form keeps its input. */
export function contactStatusKey(status: number): 'rateLimited' | 'invalid' | 'retryLater' | 'error' {
  if (isRetryLater(status)) return 'retryLater';
  if (status === 429) return 'rateLimited';
  if (status === 422) return 'invalid';
  return 'error';
}
