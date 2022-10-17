# helm-prepper

This script's purpose is to prepare the minimum to run a helm-chart on a cluster that have no access to the internet.  The script does the following:

- It creates a list of all the images in the chart and it's subcharts. The file is "image-list.txt"

- It imports all the public images from that list to your private container registry

- It generates a basic values file so you can start editing with the updated images references. The file name is "generated_values.yaml"


