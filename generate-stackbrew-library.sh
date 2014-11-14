#!/bin/bash
set -e

declare -A aliases
aliases=(
	[5.6]='5 latest'
)

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )
url='git://github.com/docker-library/php'

echo '# maintainer: InfoSiftr <github@infosiftr.com> (@infosiftr)'

for version in "${versions[@]}"; do
	commit="$(git log -1 --format='format:%H' -- "$version")"
	fullVersion="$(grep -m1 'ENV PHP_VERSION ' "$version/Dockerfile" | cut -d' ' -f3)"
	versionAliases=( $fullVersion $version ${aliases[$version]} )
	
	echo
	for va in "${versionAliases[@]}"; do
		if [ "$va" = 'latest' ]; then
			va='cli'
		else
			va="$va-cli"
		fi
		echo "$va: ${url}@${commit} $version"
	done
	for va in "${versionAliases[@]}"; do
		echo "$va: ${url}@${commit} $version"
	done
	
	for variant in apache fpm; do
		commit="$(git log -1 --format='format:%H' -- "$version/$variant")"
		echo
		for va in "${versionAliases[@]}"; do
			if [ "$va" = 'latest' ]; then
				va="$variant"
			else
				va="$va-$variant"
			fi
			echo "$va: ${url}@${commit} $version/$variant"
		done
	done
done
