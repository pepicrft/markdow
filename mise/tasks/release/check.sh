#!/usr/bin/env bash
#MISE description="Detect whether Markdow has releasable changes"
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
latest_version="$(git -C "${repository_root}" tag --list 'v[0-9]*' | sort -V | tail -n1)"

if [[ -n "${latest_version}" ]]; then
  next_version_number="$(git cliff --config "${repository_root}/cliff.toml" --repository "${repository_root}" --bumped-version 2>/dev/null -- "${latest_version}..HEAD" || true)"
else
  next_version_number="$(git cliff --config "${repository_root}/cliff.toml" --repository "${repository_root}" --bumped-version 2>/dev/null || true)"
fi

while [[ "${next_version_number}" == v* ]]; do
  next_version_number="${next_version_number#v}"
done

should_release=false
latest_version_number="${latest_version#v}"

if [[ -z "${latest_version}" ]]; then
  next_version_number="${next_version_number:-0.1.0}"
  should_release=true
elif [[ -n "${next_version_number}" && "${next_version_number}" != "${latest_version_number}" ]]; then
  greatest_version="$(printf '%s\n%s\n' "${latest_version_number}" "${next_version_number}" | sort -V | tail -n1)"
  if [[ "${greatest_version}" == "${next_version_number}" ]]; then
    should_release=true
  else
    next_version_number="${latest_version_number}"
  fi
else
  next_version_number="${latest_version_number}"
fi

next_version="v${next_version_number}"

printf 'latest: %s\nnext: %s\nrelease: %s\n' "${latest_version:-<none>}" "${next_version}" "${should_release}"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'should-release=%s\n' "${should_release}" >> "${GITHUB_OUTPUT}"
  printf 'next-version=%s\n' "${next_version}" >> "${GITHUB_OUTPUT}"
  printf 'next-version-number=%s\n' "${next_version_number}" >> "${GITHUB_OUTPUT}"
fi
