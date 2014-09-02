#!/bin/bash
set -e

declare -A gpgKeys
gpgKeys=(
	[5.6]='6E4F6AB321FDC07F2C332E3AC2BF0BC433CFC8B3 0BD78B5F97500D450838F95DFE857D9A90D90EC1'
	[5.5]='0BD78B5F97500D450838F95DFE857D9A90D90EC1 0B96609E270F565C13292B24C13C70B87267B52D'
	[5.4]='F38252826ACD957EF380D39F2F7956BC5DA04B5D'
	[5.3]='0B96609E270F565C13292B24C13C70B87267B52D 0A95E9A026542D53835E3F3A7DEC4E69FC9C83D7'
)
# see http://php.net/downloads.php

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

packagesUrl='http://php.net/releases/index.php?serialize=1&version=5&max=100'
packages="$(echo "$packagesUrl" | sed -r 's/[^a-zA-Z.-]+/-/g')"
curl -sSL "${packagesUrl}" > "$packages"

for version in "${versions[@]}"; do
	fullVersion="$(sed 's/;/;\n/g' $packages | grep -e 'php-'"$version"'.*\.tar\.bz2' | sed -r 's/.*php-('"$version"'[^"]+)\.tar\.bz2.*/\1/' | sort -V | tail -1)"
	gpgKey="${gpgKeys[$version]}"
	if [ -z "$gpgKey" ]; then
		echo >&2 "ERROR: missing GPG key fingerprint for $version"
		echo >&2 "  try looking on http://php.net/downloads.php#gpg-$version"
		exit 1
	fi
	
	insert="$(cat "Dockerfile-apache-insert" | sed 's/[\]/\\&/g')"
	(
		set -x
		sed -ri '
			s/^(ENV PHP_VERSION) .*/\1 '"$fullVersion"'/;
			s/^(RUN gpg .* --recv-keys) [0-9a-fA-F ]*$/\1 '"$gpgKey"'/
		' "$version/Dockerfile"
		
		awk -vf2="$insert" '/^\t&& make install \\$/{print f2;next}1' "$version/Dockerfile" "Dockerfile-apache-tail" > "$version/apache/Dockerfile"
	)
done

rm "$packages"
