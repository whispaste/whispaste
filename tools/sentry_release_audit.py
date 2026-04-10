import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlparse
from urllib.request import Request, urlopen


DEFAULT_ERROR_QUERY = 'is:unresolved level:error'
DEFAULT_WARNING_QUERY = 'is:unresolved level:warning'


def split_env_values(value: str | None) -> list[str]:
    if not value:
        return []
    parts = re.split(r'[;,]', value)
    return [part.strip() for part in parts if part.strip()]


def derive_base_url_from_dsn(dsn: str | None) -> str | None:
    if not dsn:
        return None
    parsed = urlparse(dsn)
    if not parsed.scheme:
        return None
    host = parsed.netloc.split('@')[-1]
    if host.startswith('ingest.'):
        host = host[len('ingest.') :]
    return f'{parsed.scheme}://{host}'


def build_query(base_query: str, projects: list[str], environments: list[str]) -> str:
    parts = [base_query.strip()]
    parts.extend(f'project:{project}' for project in projects)
    parts.extend(f'environment:{environment}' for environment in environments)
    return ' '.join(part for part in parts if part)


def extract_next_cursor(link_header: str | None) -> str | None:
    if not link_header:
        return None
    for segment in link_header.split(','):
        if 'rel="next"' not in segment or 'results="true"' not in segment:
            continue
        match = re.search(r'cursor="([^"]+)"', segment)
        if match:
            return match.group(1)
    return None


def request_json(
    *,
    base_url: str,
    path: str,
    token: str,
    params: dict[str, Any],
) -> tuple[list[dict[str, Any]], str | None]:
    url = f"{base_url.rstrip('/')}{path}"
    query = urlencode(params, doseq=True, quote_via=quote)
    request = Request(
        f'{url}?{query}',
        headers={
            'Authorization': f'Bearer {token}',
            'Accept': 'application/json',
            'User-Agent': 'whispaste-sentry-release-audit/1.0',
        },
    )
    with urlopen(request, timeout=30) as response:
        body = response.read().decode('utf-8')
        payload = json.loads(body)
        if not isinstance(payload, list):
            raise RuntimeError('Expected a list response from Sentry issues API.')
        return payload, response.headers.get('Link')


def fetch_issues(
    *,
    base_url: str,
    organization: str,
    token: str,
    query: str,
    limit: int,
    max_pages: int,
) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    cursor: str | None = None
    pages = 0
    path = f'/api/0/organizations/{quote(organization)}/issues/'
    while pages < max_pages and len(issues) < limit:
        page_limit = min(100, limit - len(issues))
        params: dict[str, Any] = {
            'query': query,
            'limit': page_limit,
        }
        if cursor:
            params['cursor'] = cursor
        batch, link_header = request_json(
            base_url=base_url,
            path=path,
            token=token,
            params=params,
        )
        issues.extend(batch)
        pages += 1
        cursor = extract_next_cursor(link_header)
        if not cursor or not batch:
            break
    return issues


def summarize_issue(issue: dict[str, Any]) -> dict[str, Any]:
    project = issue.get('project') or {}
    return {
        'id': issue.get('id'),
        'shortId': issue.get('shortId'),
        'title': issue.get('title'),
        'level': issue.get('level'),
        'status': issue.get('status'),
        'count': issue.get('count'),
        'userCount': issue.get('userCount'),
        'lastSeen': issue.get('lastSeen'),
        'firstSeen': issue.get('firstSeen'),
        'project': project.get('slug') or project.get('name'),
        'permalink': issue.get('permalink'),
    }


def print_text_report(report: dict[str, Any]) -> None:
    summary = report['summary']
    print('Sentry release audit')
    print(f"Generated at: {report['generatedAt']}")
    print(f"Base URL: {report['baseUrl']}")
    print(f"Organization: {report['organization']}")
    print(f"Projects: {', '.join(report['projects']) if report['projects'] else '(all)'}")
    print(
        f"Environments: {', '.join(report['environments']) if report['environments'] else '(none)'}"
    )
    print()
    print(
        f"Summary: clean={summary['clean']} errors={summary['errorIssueCount']} "
        f"warnings={summary['warningIssueCount']} total={summary['totalIssueCount']}"
    )

    for label, issues in (
        ('Error issues', report['errorIssues']),
        ('Warning issues', report['warningIssues']),
    ):
        print()
        print(f'{label}: {len(issues)}')
        for issue in issues:
            print(
                '- '
                f"[{issue.get('shortId') or issue.get('id')}] "
                f"{issue.get('title')} "
                f"(project={issue.get('project')}, status={issue.get('status')}, "
                f"count={issue.get('count')}, lastSeen={issue.get('lastSeen')})"
            )
            if issue.get('permalink'):
                print(f"  {issue['permalink']}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Pull current unresolved Sentry error/warning issues for release gating.',
    )
    parser.add_argument('--org', default=os.getenv('SENTRY_ORG'))
    parser.add_argument('--project', action='append', default=[])
    parser.add_argument('--environment', action='append', default=[])
    parser.add_argument('--base-url', default=os.getenv('SENTRY_BASE_URL'))
    parser.add_argument('--dsn', default=os.getenv('SENTRY_DSN'))
    parser.add_argument('--auth-token', default=os.getenv('SENTRY_AUTH_TOKEN'))
    parser.add_argument('--error-query', default=DEFAULT_ERROR_QUERY)
    parser.add_argument('--warning-query', default=DEFAULT_WARNING_QUERY)
    parser.add_argument('--limit', type=int, default=100)
    parser.add_argument('--max-pages', type=int, default=10)
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--fail-on-findings', action='store_true')
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    projects = list(args.project)
    projects.extend(split_env_values(os.getenv('SENTRY_PROJECT')))
    projects.extend(split_env_values(os.getenv('SENTRY_PROJECTS')))
    projects = sorted(set(projects))

    environments = list(args.environment)
    environments.extend(split_env_values(os.getenv('SENTRY_ENVIRONMENT')))
    environments.extend(split_env_values(os.getenv('SENTRY_ENVIRONMENTS')))
    environments = sorted(set(environments)) or ['production']

    base_url = args.base_url or derive_base_url_from_dsn(args.dsn) or 'https://sentry.io'

    if not args.org:
        print('Missing SENTRY_ORG or --org.', file=sys.stderr)
        return 2
    if not args.auth_token:
        print('Missing SENTRY_AUTH_TOKEN or --auth-token.', file=sys.stderr)
        return 2

    try:
        error_issues = fetch_issues(
            base_url=base_url,
            organization=args.org,
            token=args.auth_token,
            query=build_query(args.error_query, projects, environments),
            limit=args.limit,
            max_pages=args.max_pages,
        )
        warning_issues = fetch_issues(
            base_url=base_url,
            organization=args.org,
            token=args.auth_token,
            query=build_query(args.warning_query, projects, environments),
            limit=args.limit,
            max_pages=args.max_pages,
        )
    except HTTPError as error:
        body = error.read().decode('utf-8', errors='replace')
        print(f'Sentry API error: HTTP {error.code}: {body}', file=sys.stderr)
        return 2
    except URLError as error:
        print(f'Sentry API network error: {error}', file=sys.stderr)
        return 2
    except Exception as error:
        print(f'Sentry audit failed: {error}', file=sys.stderr)
        return 2

    report = {
        'generatedAt': datetime.now(timezone.utc).isoformat(),
        'baseUrl': base_url,
        'organization': args.org,
        'projects': projects,
        'environments': environments,
        'queries': {
            'error': build_query(args.error_query, projects, environments),
            'warning': build_query(args.warning_query, projects, environments),
        },
        'summary': {
            'clean': not error_issues and not warning_issues,
            'errorIssueCount': len(error_issues),
            'warningIssueCount': len(warning_issues),
            'totalIssueCount': len(error_issues) + len(warning_issues),
        },
        'errorIssues': [summarize_issue(issue) for issue in error_issues],
        'warningIssues': [summarize_issue(issue) for issue in warning_issues],
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print_text_report(report)

    if args.fail_on_findings and not report['summary']['clean']:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
