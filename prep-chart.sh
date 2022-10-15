#!/bin/bash

helmChartName="argo-cd"
helmChartUrl="https://argoproj.github.io/argo-helm"
helmChartVersion="5.6.0"
targetRegistry="myacr.azurecr.io"

get_chart(){
  helm repo add $helmChartName $helmChartUrl
  if [ ! -f "$helmChartName-$helmChartVersion.tgz" ]; then
    helm pull $helmChartName/$helmChartName --version $helmChartVersion
  else
    echo "[Info] The chart's tarball is already present. No need to pull"
    tar xfz $helmChartName-$helmChartVersion.tgz
  fi
}

create_list(){
  helm template argo-cd \
    | yq '..|.image? | select(.)' \
    | sort -u \
    | sed 's/---//' \
    | sed -r '/^\s*$/d' > image-list.txt
}

create_values_file(){
  echo "---" > generated_values.yaml
  while read i; do
    imageRepo=${i%:*}
    # imageRepoRegistry=$(cut -d '/' -f 1 <<< $imageRepo)
    imageWithoutRegistry=$(echo $imageRepo | sed "s/^[^\/]*\///g" )
    newTargetImage=$targetRegistry/$imageWithoutRegistry
    # echo "imageRepoRegistry = "$imageRepoRegistry
    # echo "imageWithoutRegistry = "$imageWithoutRegistry
    # echo "newTargetImage = "$newTargetImage
    imageTag=${i#*:}
    yamlPath=$(yq '.. | select(. == '\"$imageRepo\"') | path' $helmChartName/values.yaml \
      | sed 's/-//; s/ //; s/^/./' \
      | tr -d '\n')
    yamlPathRootKey=$(cut -d '.' -f 2 <<< $yamlPath )
    yq -n '('$yamlPath' = '\"$newTargetImage\"')' > temp
    cat temp | yq .$yamlPathRootKey'.image += {"tag": '\"$imageTag\"'}' >> generated_values.yaml
    rm -rf temp
  done < image-list.txt
  echo "[Info] Success! Here is the content of your generated_values.yaml:"
  cat generated_values.yaml
}

import_to_acr(){
  if [[ $(wc -l < image-list.txt) -gt 1 ]]; then
    az acr login -n $targetRegistry
    while read source; do
      tag="$targetRegistry/$(printf -- "%s" "${source#*/}")"
      echo "Building $source with tag $tag"
      dockerfile=$(cat Dockerfile-label.template | sed -e "s#%%SOURCE%%#$source#g")
      echo "$dockerfile"
      echo
      echo "$dockerfile" | docker build -t $tag -
      if [ $? -eq 0 ]; then
        echo "Build successful, now pushing"
        docker push $tag
      else
        echo "Error, stopping script"
        exit 1
      fi
    done < image-list.txt
  else
    echo "The image-list.txt file is empty or inexistant. Couldn't run the script."
  fi
}

get_chart
create_list
import_to_acr
create_values_file
