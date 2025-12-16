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


# terraform plan -var="eks_version=$3" -var="eks_nodegroup_version=$4" -out=tfplan | tee -a "$LOG_FILE"
# terraform show tfplan | tee -a "$LOG_FILE"

# echo -e "${Y}Review the plan above carefully.${N}"
# read -p "Type YES to continue with terraform apply: " CONFIRM

# if [ "$CONFIRM" != "YES" ]; then
#   echo -e "${R}Terraform apply aborted by user${N}" | tee -a "$LOG_FILE"
#   exit 1
# fi
# terraform apply tfplan

