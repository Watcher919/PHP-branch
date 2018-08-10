#!/usr/bin/env bash
set -Eeuo pipefail

declare -A aliases=(
	[5.6]='5'
	[7.2]='7 latest'
	[7.3-rc]='rc'
)

defaultDebianSuite='stretch'
defaultAlpineVersion='3.8'

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )

# sort version numbers with highest first
IFS=$'\n'; versions=( $(echo "${versions[*]}" | sort -rV) ); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

getArches() {
	local repo="$1"; shift
	local officialImagesUrl='https://github.com/docker-library/official-images/raw/master/library/'

	eval "declare -g -A parentRepoToArches=( $(
		find -name 'Dockerfile' -exec awk '
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|microsoft\/[^:]+)(:|$)/ {
					print "'"$officialImagesUrl"'" $2
				}
			' '{}' + \
			| sort -u \
			| xargs bashbrew cat --format '[{{ .RepoName }}:{{ .TagName }}]="{{ join " " .TagEntry.Architectures }}"'
	) )"
}
getArches 'php'

cat <<-EOH
# this file is generated via https://github.com/docker-library/php/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/php.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version in "${versions[@]}"; do

	versionAliases=(
		$version
		${aliases[$version]:-}
	)

	# order here controls the order of the library/ file
	for suite in \
		stretch \
		jessie \
		alpine{3.8,3.7,3.6} \
	; do
		for variant in \
			cli \
			apache \
			fpm \
			zts \
		; do
			dir="$version/$suite/$variant"
			[ -f "$dir/Dockerfile" ] || continue

			commit="$(dirCommit "$dir")"
			fullVersion="$(git show "$commit":"$dir/Dockerfile" | awk '$1 == "ENV" && $2 == "PHP_VERSION" { print $3; exit }')"

			baseAliases=( $fullVersion "${versionAliases[@]}" )
			variantAliases=( "${baseAliases[@]/%/-$variant}" )
			variantAliases=( "${variantAliases[@]//latest-/}" )

			if [ "$variant" = 'cli' ]; then
				variantAliases+=( "${baseAliases[@]}" )
			fi

			suiteVariantAliases=( "${variantAliases[@]/%/-$suite}" )
			if [ "${suite#alpine}" = "$defaultAlpineVersion" ] ; then
				variantAliases=( "${variantAliases[@]/%/-alpine}" )
			elif [ "$suite" != "$defaultDebianSuite" ]; then
				variantAliases=()
			fi
			variantAliases=( "${suiteVariantAliases[@]}" ${variantAliases[@]+"${variantAliases[@]}"} )
			variantAliases=( "${variantAliases[@]//latest-/}" )

			variantParent="$(awk 'toupper($1) == "FROM" { print $2 }' "$dir/Dockerfile")"
			variantArches="${parentRepoToArches[$variantParent]}"

			# 7.2 no longer supports s390x
			# #error "Not yet implemented"
			# https://github.com/docker-library/php/pull/487#issue-254755661
			if [[ "$version" = 7.* ]] && [ "$version" != '7.0' ] && [ "$version" != '7.1' ]; then
				variantArches="$(echo " $variantArches " | sed -r -e 's/ s390x//g')"
			fi

			echo
			cat <<-EOE
				Tags: $(join ', ' "${variantAliases[@]}")
				Architectures: $(join ', ' $variantArches)
				GitCommit: $commit
				Directory: $dir
			EOE
		done
	done
done
