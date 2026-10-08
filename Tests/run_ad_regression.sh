#!/bin/sh
set -eu
ad_tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ad_repo_dir=$(dirname "$ad_tests_dir")
ad_test_work=$(mktemp -d /tmp/super-parakeet-ad-regression.XXXXXX)
trap 'rm -rf "$ad_test_work"' EXIT
cp "$ad_repo_dir/super-parakeet/Service/AdLifecycle.swift" "$ad_test_work/AdLifecycle.swift"
cp "$ad_tests_dir/AdLifecycle/main.swift" "$ad_test_work/main.swift"
xcrun swiftc -swift-version 5 -module-cache-path "$ad_test_work/modules" "$ad_test_work/AdLifecycle.swift" "$ad_test_work/main.swift" -o "$ad_test_work/regression"
"$ad_test_work/regression"
