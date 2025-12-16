#!/bin/bash

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

CLUSTER_NAME="roboshop-dev"
AWS_REGION="us-east-1"
EKS_TARGET_VERSION=$1
CURRENT_NG_VERSION=$2
TARGET_NG_VERSION=""
ADDONS=("vpc-cni" "coredns" "kube-proxy" "eks-pod-identity-agent" "metrics-server")


LOGS_FOLDER="/var/log/eks-upgrade"
SCRIPT_NAME=$( echo $0 | cut -d "." -f1 )
SCRIPT_DIR=$PWD
LOG_FILE="$LOGS_FOLDER/$SCRIPT_NAME.log" # /var/log/shell-script/16-logs.log

#mkdir -p $LOGS_FOLDER
echo "Script started executed at: $(date)" | tee -a $LOG_FILE

if [ "$#" -ne 2 ]; then
  echo -e "${R}Usage:${N} $0 <EKS_TARGET_VERSION> <CURRENT_NG_VERSION>" | tee -a "$LOG_FILE"
  echo -e "${R}Example:${N} $0 1.34 green" | tee -a "$LOG_FILE"
  exit 1
fi

# Validate CURRENT_NG_VERSION
if [[ "$CURRENT_NG_VERSION" != "blue" && "$CURRENT_NG_VERSION" != "green" ]]; then
  echo -e "${R}CURRENT_NG_VERSION must be either 'blue' or 'green'${N}" | tee -a "$LOG_FILE"
  exit 1
fi

# Auto-derive TARGET_NG_VERSION
if [[ "$CURRENT_NG_VERSION" == "blue" ]]; then
  TARGET_NG_VERSION="green"
else
  TARGET_NG_VERSION="blue"
fi

VALIDATE(){ # functions receive inputs through args just like shell script args
    if [ $1 -ne 0 ]; then
        echo -e "$2 ... $R FAILURE $N" | tee -a $LOG_FILE
        exit 1
    else
        echo -e "$2 ... $G SUCCESS $N" | tee -a $LOG_FILE
    fi
}

CURRENT_CP_VERSION=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.version' \
  --output text)
VALIDATE $? "Fetch current control plane version"

echo -e "${Y}Current CP version: ${CURRENT_CP_VERSION}${N}" | tee -a "$LOG_FILE"
echo -e "${Y}Target  CP version: ${EKS_TARGET_VERSION}${N}" | tee -a "$LOG_FILE"

CUR_MAJOR=$(echo "$CURRENT_CP_VERSION" | cut -d. -f1)
CUR_MINOR=$(echo "$CURRENT_CP_VERSION" | cut -d. -f2)

TGT_MAJOR=$(echo "$EKS_TARGET_VERSION" | cut -d. -f1)
TGT_MINOR=$(echo "$EKS_TARGET_VERSION" | cut -d. -f2)

# basic sanity
if [[ -z "$CUR_MAJOR" || -z "$CUR_MINOR" || -z "$TGT_MAJOR" || -z "$TGT_MINOR" ]]; then
  echo -e "${R}Unable to parse versions. current=$CURRENT_CP_VERSION target=$EKS_TARGET_VERSION${N}" | tee -a "$LOG_FILE"
  exit 1
fi

# must be same major and exactly +1 minor
if [[ "$CUR_MAJOR" != "$TGT_MAJOR" || $((TGT_MINOR - CUR_MINOR)) -ne 1 ]]; then
  echo -e "${R}ABORT:${N} Target version must be exactly one minor step ahead. current=$CURRENT_CP_VERSION target=$EKS_TARGET_VERSION" | tee -a "$LOG_FILE"
  exit 1
fi

echo -e "${G}Version check passed:${N} $CURRENT_CP_VERSION -> $EKS_TARGET_VERSION" | tee -a "$LOG_FILE"

echo -e "$Y Upgrading Control plane version $N"
# aws eks update-cluster-version \
#   --name "$CLUSTER_NAME" \
#   --region "$AWS_REGION" \
#   --kubernetes-version "$EKS_TARGET_VERSION" &>> "$LOG_FILE"
VALIDATE $? "Trigger control plane upgrade"

#wait_cluster_upgraded "$EKS_TARGET_VERSION"

wait_cluster_upgraded() {
  local expected="$1"
  echo -e "${Y}Waiting for cluster to become ACTIVE and version=$expected...${N}" | tee -a "$LOG_FILE"

  while true; do
    status=$(get_cluster_status)
    version=$(get_cluster_version)

    echo "Cluster status=$status version=$version" | tee -a "$LOG_FILE"

    if [[ "$status" == "ACTIVE" && "$version" == "$expected" ]]; then
      echo -e "${G}Control plane upgraded successfully to $version${N}" | tee -a "$LOG_FILE"
      break
    fi

    if [[ "$status" == "FAILED" ]]; then
      echo -e "${R}Control plane upgrade FAILED${N}" | tee -a "$LOG_FILE"
      exit 1
    fi
    sleep 60
  done
}

get_cluster_status() {
  aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query 'cluster.status' --output text
}

get_cluster_version() {
  aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query 'cluster.version' --output text
}

addon_installed() {
  aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$1" \
    --region "$AWS_REGION" \
    --query 'addon.addonName' --output text >/dev/null 2>&1
}

addon_version() {
  aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$1" \
    --region "$AWS_REGION" \
    --query 'addon.addonVersion' --output text 2>/dev/null || echo "UNKNOWN"
}

latest_compatible_addon_version() {
  local addon="$1"
  local cp_ver="$2"

  aws eks describe-addon-versions \
    --addon-name "$addon" \
    --region "$AWS_REGION" \
    --query "addons[0].addonVersions[?compatibilities[?clusterVersion=='${cp_ver}']]|[-1].addonVersion" \
    --output text 2>/dev/null || echo "None"
}



wait_addon_active_and_version(){
  local addon="$1"
  local expected="$2"
  echo -e "${Y}Waiting for addon $addon to be ACTIVE at version=$expected ...${N}"
  while true; do
    local st ver
    st=$(addon_status "$addon")
    ver=$(addon_version "$addon")
    echo -e "Addon $addon status=$st version=$ver"
    if [[ "$st" == "ACTIVE" && "$ver" == "$expected" ]]; then
      echo -e "${G}Addon $addon upgraded OK: $ver${N}"
      break
    fi
    if [[ "$st" == "DEGRADED" || "$st" == "UPDATE_FAILED" || "$st" == "FAILED" ]]; then
      echo -e "${R}Addon $addon upgrade problem: status=$st${N}"
      exit 1
    fi
    if [[ "$st" == "MISSING" ]]; then
      log "${Y}Addon $addon not installed. Skipping wait.${N}"
      break
    fi
    sleep 20
  done
}

upgrade_addons_to_latest_compatible(){
  local cp_ver="$1"
  for addon in "${ADDONS[@]}"; do
    if ! addon_installed "$addon"; then
      echo -e "${Y}Addon $addon not installed on cluster. Skipping.${N}"
      continue
    fi

    local current latest
    current=$(addon_version "$addon")
    latest=$(latest_compatible_addon_version "$addon" "$cp_ver")
    echo "DEBUG: addon=$addon cp_ver=$cp_ver latest='$latest'" | tee -a "$LOG_FILE"

    if [[ -z "$latest" || "$latest" == "None" ]]; then
      echo -e "${R}Could not find compatible latest version for addon $addon on cluster $cp_ver${N}"
      exit 1
    fi

    echo -e "${Y}Addon $addon current=$current latest_compatible=$latest${N}"

    if [[ "$current" == "$latest" ]]; then
      echo -e "${G}Addon $addon already at latest compatible version${N}"
      continue
    fi

    # aws eks update-addon \
    #   --cluster-name "$CLUSTER_NAME" \
    #   --addon-name "$addon" \
    #   --addon-version "$latest" \
    #   --resolve-conflicts PRESERVE \
    #   --region "$AWS_REGION" &>> "$LOG_FILE"
    # VALIDATE $? "Update addon $addon -> $latest"

    # wait_addon_active_and_version "$addon" "$latest"
  done
}




upgrade_addons_to_latest_compatible "$EKS_TARGET_VERSION"

# terraform plan -var="eks_version=$3" -var="eks_nodegroup_version=$4" -out=tfplan | tee -a "$LOG_FILE"
# terraform show tfplan | tee -a "$LOG_FILE"

# echo -e "${Y}Review the plan above carefully.${N}"
# read -p "Type YES to continue with terraform apply: " CONFIRM

# if [ "$CONFIRM" != "YES" ]; then
#   echo -e "${R}Terraform apply aborted by user${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi
# terraform apply tfplan

