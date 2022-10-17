#!/bin/bash

helmChartName="kube-prometheus-stack"
helmChartUrl="https://prometheus-community.github.io/helm-charts"
helmChartVersion="41.4.1"
targetRegistry="myacr.azurecr.io"

get_chart(){
  helm repo add "$helmChartName-repo" $helmChartUrl
  if [ ! -f "$helmChartName-$helmChartVersion.tgz" ]; then
    helm pull $helmChartName-repo/$helmChartName --version $helmChartVersion
    tar xfz $helmChartName-$helmChartVersion.tgz
  else
    echo "[Info] The chart's tarball is already present. No need to pull"
    tar xfz $helmChartName-$helmChartVersion.tgz
  fi
  grep -q $helmChartName .gitignore || echo $helmChartName >> .gitignore
  grep -q $helmChartName .gitignore || echo $helmChartName >> .gitignore
}

create_list(){
  helm template $helmChartName \
    | yq '..|.image? | select(.)' \
    | sort -u \
    | sed 's/---//' \
    | sed -r '/^\s*$/d' > image-list.txt
}

create_values_file(){
  mkdir ./tmp
  echo "---" > generated_values.yaml
  loopCounter=0
  while read i; do
    loopCounter=$(($loopCounter+1))
    imageRepo=${i%:*}
    imageWithoutRegistry=$(echo $imageRepo | sed "s/^[^\/]*\///g" )
    newTargetImage=$targetRegistry/$imageWithoutRegistry
    imageTag=${i#*:}
    yamlPath=$(yq '.. | select(. == '\"$imageRepo\"') | path' $helmChartName/values.yaml \
      | sed 's/-//; s/ //; s/^/./' \
      | tr -d '\n')
    yamlPathToImage=$(sed "s/\.image.*//g" <<< $yamlPath)

    if [ ! -z $yamlPathToImage ]; then
      yq -n '('$yamlPath' = '\"$newTargetImage\"')' > temp.yaml
      cat temp.yaml | yq $yamlPathToImage'.image += {"tag": '\"$imageTag\"'}' >> ./tmp/generated_values-$loopCounter.yaml
    else
      echo "[Info] couldnt find image $imageRepo in main chart. will look into subchart"
      subValuesFile=$(grep -inrl --include \values.yaml $imageRepo)
      subChart=$(sed "s/\/values\.yaml//" <<< $subValuesFile | sed "s:.*/::" )
      subchartYamlPath=.$subChart$(yq '.. | select(. == '\"$imageRepo\"') | path' $subValuesFile \
      | sed 's/-//; s/ //; s/^/./' \
      | tr -d '\n') 
      
      yq -n '('$subchartYamlPath' = '\"$newTargetImage\"')' > temp.yaml
      cat temp.yaml | yq ${subchartYamlPath%.*}' += {"tag": '\"$imageTag\"'}' >> ./tmp/generated_values-$loopCounter.yaml
    fi
    rm -rf temp.yaml
  done < image-list.txt
  yq eval-all '. as $item ireduce ({}; . * $item )' ./tmp/*.yaml >> generated_values.yaml
  # rm -rf ./tmp
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

# get_chart
# create_list
# import_to_acr
create_values_file
