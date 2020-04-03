#!/bin/bash -e
#
# Copyright (c) 2020 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, v. 2 except as noted otherwise in the LICENSE file
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

__tmp_imagevector_overwrite=""
mktemp_imagevector_overwrite() {
  if [[ "$__tmp_imagevector_overwrite" != "" ]]; then
    echo "$__tmp_imagevector_overwrite"
    return
  fi

  __tmp_imagevector_overwrite="$(mktemp)"
  compute_imagevector_overwrite > "$__tmp_imagevector_overwrite"
  echo "$__tmp_imagevector_overwrite"
}

cleanup_imagevector_overwrite() {
  if [[ "$__tmp_imagevector_overwrite" != "" ]]; then
    rm -f "$__tmp_imagevector_overwrite"
    __tmp_imagevector_overwrite=""
  fi
}

compute_imagevector_overwrite() {
  imagevector_overwrite="images: []"

  VERSION="$(cat $(dirname $0)/../VERSION)"
  if [[ "$VERSION" != *"-dev"* ]]; then
    echo "$imagevector_overwrite"
    return
  fi

  gardener_images_without_tag="$(yaml2json < "$(dirname $0)/../charts/images.yaml" | jq -r '.images | map(select(.sourceRepository == "github.com/gardener/gardener-extension-runtime-gvisor" and .tag == null))')"
  if [[ "$(echo $gardener_images_without_tag | jq -r 'length')" == "0" ]]; then
    echo "$imagevector_overwrite"
    return
  fi

  git fetch origin
  last_known_upstream_image_tag="$VERSION-$(git merge-base origin/master HEAD)"
  current_commit_image_tag="$VERSION-$(git rev-parse HEAD)"
  gcr_url_prefix="https://eu.gcr.io/v2"

  while IFS= read -r line; do
    image_name="$(echo $line | awk '{print $1}')"
    image_repo="$(echo $line | awk '{print $2}')"
    image_tag="$last_known_upstream_image_tag"

    cache_file_name="$(get_cache_file_name "$image_name" "$current_commit_image_tag")"
    if [[ ! -f "$cache_file_name" ]]; then
      curl -s "$gcr_url_prefix/$(echo "$image_repo" | sed 's/^eu\.gcr\.io\///')/manifests/$current_commit_image_tag" | jq -r '.config.size' > "$cache_file_name"
    fi
    image_size="$(cat "$cache_file_name")"

    if [[ "$image_size" != "null" ]]; then
      image_tag="$current_commit_image_tag"
    fi

    imagevector_overwrite="$(echo "$imagevector_overwrite" | yaml2json | jq ".images += [{\"name\": \"$image_name\", \"repository\": \"$image_repo\", \"tag\": \"$image_tag\"}]")"
  done < <(echo "$gardener_images_without_tag" | jq -r '.[] | "\(.name) \(.repository)"')

  echo "$imagevector_overwrite"
}

get_cache_file_name() {
  echo "/tmp/start-gvisor-extension-$1-$2-$(date +"%Y-%d-%m-%H")"
}