#!/bin/bash

#General parameters
SPARK_OPERATOR_NAMESPACE="wave-sparkoperator"
SPARK_APPLICATIONS_NAMESPACE="wave-applications"

LOG_LEVEL="info"

#PVC yaml template URL
PVC_YAML_TEMPLATE="https://raw.githubusercontent.com/alextarasov-spot/wave-sparkhistory-helm-chart/master/wave-pvc-sparkhistory-template.yaml"

#EFS provosioner DEFAULT parameters
EFS_ENABLED=false
PVC_ENABLED=true
WAVE_PVC_NAME="wave-efs"

EFS_PROVISIONER_RELEASE_NAME="wave-nfs"
EFS_PROVISIONER_SERVICE_ACCOUNT_NAME="wave-efs-provosioner"
EFS_PROVISIONER_NAME=" wave.sparkhistory/aws-efs"
WAVE_EFS_PROVISIONER_STORAGE_CLASS_NAME="wave-aws-efs"

#EFS provosioner MANDATORY parameters
EFS_FILESYSTEM_ID=""
EFS_AWS_REGION=""

#Spark History Server parameters
SPARK_HISTORY_RELEASE_NAME="wave-history"

#Spark Operator parameters
SPARK_OPERATOR_RELEASE_NAME="wave-spark"

#HELM dry-run mode
DRY_RUN=false

#create necessarry createNamespaces
function createNamespaces() {
  info "Going to create namespace $SPARK_OPERATOR_NAMESPACE"

  # verify that the SPARK_OPERATOR_NAMESPACE namespace doesn't exists
  ns=$(kubectl get namespace $SPARK_OPERATOR_NAMESPACE --no-headers --output=go-template={{.metadata.name}} 2>/dev/null)

  if [ -z "${ns}" ]; then
    kubectl create namespace $SPARK_OPERATOR_NAMESPACE
  else
    info "Namespace $SPARK_OPERATOR_NAMESPACE already exists"
  fi

  printf "\n"
  info "Going tp create namespace $SPARK_APPLICATIONS_NAMESPACE"

  # verify that the SPARK_APPLICATIONS_NAMESPACE namespace doesn't  exists
  ns=$(kubectl get namespace $SPARK_APPLICATIONS_NAMESPACE --no-headers --output=go-template={{.metadata.name}} 2>/dev/null)
  if [ -z "${ns}" ]; then
    kubectl create namespace $SPARK_APPLICATIONS_NAMESPACE
  else
    info "Namespace $SPARK_APPLICATIONS_NAMESPACE already exists"
  fi
}

function efsProvisioner() {
  if [ "$EFS_ENABLED" = false ]; then
    debug "efsEbabled set to false"
    return 0
  fi

  printf "\n"
  info "efsEbabled set to ($EFS_ENABLED). Going to install EFS Provisioner into $SPARK_APPLICATIONS_NAMESPACE namespace"
  info "EFS Provisioner Release name: ($EFS_PROVISIONER_RELEASE_NAME)"
  info "EFS Provisioner name: ($EFS_PROVISIONER_NAME)"
  info "EFS Provisioner StorageClass Name: ($WAVE_EFS_PROVISIONER_STORAGE_CLASS_NAME)"
  info "EFS File Systen ID: ($EFS_FILESYSTEM_ID)"
  info "AWS Region: ($EFS_AWS_REGION)"
  printf "\n"

  if [ -z "$EFS_FILESYSTEM_ID" ]; then
    error "efsProvisioner.efsFileSystemId is empty EXIT"
    return 1
  fi

  if [ -z "$EFS_AWS_REGION" ]; then
    error "efsProvisioner.awsRegion is empty. EXIT"
    return 1
  fi

  helm repo add stable https://kubernetes-charts.storage.googleapis.com

  helm install $EFS_PROVISIONER_RELEASE_NAME $($DRY_RUN && echo  "--dry-run --debug") stable/efs-provisioner \
    --namespace $SPARK_APPLICATIONS_NAMESPACE \
    --set efsProvisioner.provisionerName=$EFS_PROVISIONER_NAME \
    --set serviceAccount.name=$EFS_PROVISIONER_SERVICE_ACCOUNT_NAME \
    --set efsProvisioner.storageClass.name=$WAVE_EFS_PROVISIONER_STORAGE_CLASS_NAME \
    --set efsProvisioner.efsFileSystemId=$EFS_FILESYSTEM_ID \
    --set efsProvisioner.awsRegion=$EFS_AWS_REGION

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "EFS Provisioner not installed. Please check the error message above"
    return 1
  fi

  #Create PVC
  if [ "$PVC_ENABLED" = true ]; then
    createPvc
  else
    info "pvcEnabled set to FALSE. PVC won't be created. Please take a look at template above."
  fi
}

function createPvc() {
  info "Going to create PVC from template"

  debug "Namespace: ${SPARK_APPLICATIONS_NAMESPACE}"
  debug "EFS Provisioner StorageClass Name: ${WAVE_EFS_PROVISIONER_STORAGE_CLASS_NAME}"

  #Get PVC yaml from WAVE repository
  source /dev/stdin <<<"$(
    echo 'cat <<EOF >>wave-pvc-sparkhistory.yaml'
    curl -s $PVC_YAML_TEMPLATE
  )"

  finalPvcYaml=$(cat wave-pvc-sparkhistory.yaml)
  debug "PVC yaml from template was created:\n $finalPvcYaml"

  kubectl apply -f wave-pvc-sparkhistory.yaml

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "PVC not created. Please check the error message above"
    return 1
  fi

  #Remove tmp result PVC yaml
  rm wave-pvc-sparkhistory.yaml
}

function sparkHistory() {
  info "Going to install Spark History Server into $SPARK_APPLICATIONS_NAMESPACE namespace"
  printf "\n"

  helm repo add stable https://kubernetes-charts.storage.googleapis.com

  helm install $SPARK_HISTORY_RELEASE_NAME $($DRY_RUN && echo  "--dry-run --debug") stable/spark-history-server \
    --namespace $SPARK_APPLICATIONS_NAMESPACE \
    --set nfs.enableExampleNFS=false \
    --set pvc.enablePVC=$PVC_ENABLED \
    --set pvc.existingClaimName=$WAVE_PVC_NAME

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "Spark Histroy Server not installed. Please check the error message above"
    return 1
  fi
}

function sparkOperator() {
  info "Going to install Spark Operator into $SPARK_OPERATOR_NAMESPACE namespace"
  printf "\n"

  helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator

  helm install $SPARK_OPERATOR_RELEASE_NAME $($DRY_RUN && echo  "--dry-run --debug") incubator/sparkoperator \
    --namespace $SPARK_OPERATOR_NAMESPACE \
    --set sparkJobNamespace=$SPARK_APPLICATIONS_NAMESPACE \
    --set enableWebhook=true

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "Spark Operator not installed. Please check the error message above"
    return 1
  fi
}

log_level_for() {
  case "${1}" in
  "error")
    echo 1
    ;;

  "warn")
    echo 2
    ;;

  "info")
    echo 3
    ;;

  "debug")
    echo 4
    ;;
  *)
    echo -1
    ;;
  esac
}

current_log_level() {
  log_level_for "${LOG_LEVEL}"
}

error() {
  [ $(log_level_for "error") -le $(current_log_level) ] && echo "${1}" >&2
}

warn() {
  [ $(log_level_for "warn") -le $(current_log_level) ] && echo "${1}" >&2
}

debug() {
  [ $(log_level_for "debug") -le $(current_log_level) ] && echo "${1}" >&2
}

info() {
  [ $(log_level_for "info") -le $(current_log_level) ] && echo "${1}" >&2
}

function init() {
  while [[ $# -gt 0 ]]; do
    case ${1} in
    --efsEbabled)
      EFS_ENABLED="$2"
      shift
      ;;
    --efsFileSystemId)
      EFS_FILESYSTEM_ID="$2"
      shift
      ;;
    --efsAwsRegion)
      EFS_AWS_REGION="$2"
      shift
      ;;
    --efsProvisionerName)
      EFS_PROVISIONER_NAME="$2"
      shift
      ;;
    --pvcEnabled)
      PVC_ENABLED="$2"
      shift
      ;;
    --dryRun)
      DRY_RUN="$2"
      shift
      ;;
    *)
      usage
      ;;
    esac
    shift
  done
}

function main() {
  createNamespaces
  efsProvisioner
  sparkHistory
  sparkOperator
}

init "$@"
main "$@"
