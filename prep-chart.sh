#!/bin/bash

helmChartName="argo-cd"
helmChartUrl="https://argoproj.github.io/argo-helm"
helmChartVersion="5.6.0"


helm repo add $helmChartName $helmChartUrl
helm pull $helmChartName/$helmChartName --version $helmChartVersion
tar xvfz $helmChartName-$helmChartVersion.tgz


create_list(){
  helm template argo-cd \
      | yq '..|.image? | select(.)' \
      | sort -u \
      | sed 's/---//' \
      | sed -r '/^\s*$/d' > image-list.txt
}

create_value_file(){
  echo "---" > generated_values.yaml
  while read i; do
    imageRepo=${i%:*}
    yamlPath=$(yq '.. | select(. == '\"$imageRepo\"') | path' $helmChartName/values.yaml \
      | sed 's/-//; s/ //; s/^/./' \
      | tr -d '\n')
    yq -n '('$yamlPath' = '\"$imageRepo\"')' >> generated_values.yaml
  done < image-list.txt
}


create_list
create_value_file