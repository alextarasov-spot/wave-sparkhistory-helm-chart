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
EFS_PROVISIONER_NAME="wave.sparkhistory/aws-efs"
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

#UNINSTALL mode
UNINSTALL=false

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
  info "Going to create namespace $SPARK_APPLICATIONS_NAMESPACE"

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

  helm repo add stable https://kubernetes-charts.storage.googleapis.com

  helm install $EFS_PROVISIONER_RELEASE_NAME $($DRY_RUN && echo "--dry-run --debug") stable/efs-provisioner \
    --namespace $SPARK_APPLICATIONS_NAMESPACE \
    --set efsProvisioner.provisionerName=$EFS_PROVISIONER_NAME \
    --set serviceAccount.name=$EFS_PROVISIONER_SERVICE_ACCOUNT_NAME \
    --set efsProvisioner.storageClass.name=$WAVE_EFS_PROVISIONER_STORAGE_CLASS_NAME \
    --set efsProvisioner.efsFileSystemId=$EFS_FILESYSTEM_ID \
    --set efsProvisioner.awsRegion=$EFS_AWS_REGION

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: EFS Provisioner not installed. Please check the error message above"
    exit 1
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
  debug "wave-pvc-sparkhistory.yaml\n $finalPvcYaml"

  kubectl apply -f wave-pvc-sparkhistory.yaml

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: PVC not created. Please check the error message above"
    exit 1
  fi

  #Remove tmp result PVC yaml
  rm wave-pvc-sparkhistory.yaml
}

function sparkHistory() {
  info "Going to install Spark History Server into $SPARK_APPLICATIONS_NAMESPACE namespace"
  printf "\n"

  helm repo add stable https://kubernetes-charts.storage.googleapis.com

  helm install $SPARK_HISTORY_RELEASE_NAME $($DRY_RUN && echo "--dry-run --debug") stable/spark-history-server \
    --namespace $SPARK_APPLICATIONS_NAMESPACE \
    --set nfs.enableExampleNFS=false \
    --set pvc.enablePVC=$PVC_ENABLED \
    --set pvc.existingClaimName=$WAVE_PVC_NAME

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: Spark Histroy Server not installed. Please check the error message above"
    exit 1
  fi
}

function sparkOperator() {
  info "Going to install Spark Operator into $SPARK_OPERATOR_NAMESPACE namespace"
  printf "\n"

  helm repo add incubator http://storage.googleapis.com/kubernetes-charts-incubator

  helm install $SPARK_OPERATOR_RELEASE_NAME $($DRY_RUN && echo "--dry-run --debug") incubator/sparkoperator \
    --namespace $SPARK_OPERATOR_NAMESPACE \
    --set sparkJobNamespace=$SPARK_APPLICATIONS_NAMESPACE \
    --set enableWebhook=true

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: Spark Operator not installed. Please check the error message above"
    exit 1
  fi
}

function validation() {
  #Validate EFS mandatory parameters if efsEnambled
  if [ "$EFS_ENABLED" = true ]; then
    if [ -z "$EFS_FILESYSTEM_ID" ]; then
      error "ERROR: efsProvisioner.efsFileSystemId is empty EXIT"
      exit 1
    fi

    if [ -z "$EFS_AWS_REGION" ]; then
      error "ERROR: efsProvisioner.awsRegion is empty. EXIT"
      exit 1
    fi
  fi
}

function uninstall() {
  if [ "$UNINSTALL" = false ]; then
    return 0
  fi

  warn "WARNING: You are about to uninstall resources creaed by Wave!
        This includes Sprak-Operator,Spark-History and wave-applications namespaces"

  echo "Do you want to uninstall?"

  select yn in "Yes" "No"; do
    case $yn in
    Yes)
      uninstallSparkOperator
      uninstallSparkHistory
      uninstallEfsProvisioner
      break
      ;;
    No) exit ;;
    esac
  done

  info "Uninstalled successfully"

  exit 0
}

function uninstallSparkOperator() {
  info "Going to uninstall Spark Operator"

  helm uninstall $SPARK_OPERATOR_RELEASE_NAME --namespace $SPARK_OPERATOR_NAMESPACE

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: Couldn't uninstall Spark Operator. Please check the error message above"
    exit 1
  fi
}

function uninstallSparkHistory() {
  info "Going to uninstall Spark History"

  helm uninstall $SPARK_HISTORY_RELEASE_NAME --namespace $SPARK_APPLICATIONS_NAMESPACE

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: Couldn't uninstall Spark History. Please check the error message above"
    exit 1
  fi
}

function uninstallEfsProvisioner() {
  if [ "$EFS_ENABLED" = false ]; then
    info "efsEbabled set to false. EFS Provisioner won't be uninstalled"
    return 0
  fi

  info "Going to uninstall EFS Provisioner"

  helm uninstall $EFS_PROVISIONER_RELEASE_NAME --namespace $SPARK_APPLICATIONS_NAMESPACE

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: Couldn't uninstall EFS Provisioner. Please check the error message above"
    exit 1
  fi

  if [ "$PVC_ENABLED" = false ]; then
    info "pvcEbabled set to false. PVC $WAVE_PVC_NAME won't be deleted"
    return 0
  fi

  info "Going to delete PVC"
  kubectl delete pvc $WAVE_PVC_NAME -n $SPARK_APPLICATIONS_NAMESPACE

  if [ $? -gt 0 ]; then
    printf "\n\n\t\t"
    error "ERROR: Couldn't delete PVC. Please check the error message above"
    exit 1
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

function usage() {
	cat <<EOF
Install and configure all prerequisites for Wave product by Spot
Usage:
  ${0} [flags]
Flags:
  --efs-enabled         Enable EFS for spark history setup
  --efs-file-system-id  EFS FileSystemID for spark history Setup
  --efs-aws-region      EFS Region location
  --pvc-enabled         creating PVC for spark history deployment
  --dry-run
  --uninstall           Delete all deployments/configs installed by Wave
EOF
    exit 1
}

function init() {
  while [[ $# -gt 0 ]]; do
    case ${1} in
    --efs-enabled)
      EFS_ENABLED="$2"
      shift
      ;;
    --efs-file-system-id)
      EFS_FILESYSTEM_ID="$2"
      shift
      ;;
    --efs-aws-region)
      EFS_AWS_REGION="$2"
      shift
      ;;
    --efsProvisionerName)
      EFS_PROVISIONER_NAME="$2"
      shift
      ;;
    --pvc-enabled)
      PVC_ENABLED="$2"
      shift
      ;;
    --dry-run)
      DRY_RUN="$2"
      shift
      ;;
    --uninstall)
      UNINSTALL="$2"
      shift
      ;;
    *)
      usage
      ;;
    esac
    shift
  done

  if [ "$DRY_RUN" = true ]; then
    LOG_LEVEL="debug"
  fi
}

function main() {
  uninstall
  validation
  createNamespaces
  efsProvisioner
  sparkHistory
  sparkOperator
}

init "$@"
main "$@"
