/**
 * whispaste-api answers 503 (`Retry-After`, problem code `store_unavailable`)
 * when its database is unreachable. Nothing was stored: the page must say
 * "not done, try again later", never success and never "link invalid". The
 * visitor retries by hand; there is no automatic retry loop.
 */
/** Any 503 (API store outage, failover page) means nothing was stored: try again later. */
export function isRetryLater(status: number): boolean {
  return status === 503;
}
