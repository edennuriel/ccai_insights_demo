#!/usr/bin/env bash
#set -x
#[[ -n $1 ]] && PROJECT_ID=$1
#[[ -z $PROJECT_ID ]] && PROJECT_ID="$DEVSHELL_PROJECT_ID" 
#[[ -z $PROJECT_ID ]] && echo "can not detrmine project name" && return 1
#[[ "$(gcloud projects list | grep "$PROJECT_ID")" =~  "$PROJECT_ID" ]] && FOUND=0 || FOUND=1
#echo "FOUND $FOUND ****"
#[[ $FOUND ]] && echo "can not find project" && return 1
# gcloud config set project $PROJCET_ID

reset_org_policy_for_project () {
  gcloud org-policies --project "$PROJECT_ID" list --show-unset --format="value(constraint)" | xargs -n 1 gcloud org-policies --project "$PROJECT_ID" reset
}

reset_inherited_policies() {
  echo "resetting org policies to google default - use for short lived projects only"
  gcloud org-policies list --organization=$(get_top_org) --format="value(constraint)" | xargs -n 1 $echo gcloud org-policies --project "$PROJECT_ID" reset
}

list_inherited_polices() {
  gcloud org-policies list --organization=$(get_top_org) --format="value(constraint)" | awk '{printf "\""$1"\","}' | sed 's/,$//' | awk '{print "["$1"]"}'
}  

get_top_org() {
  gcloud organizations list --format="get(name)" | cut -f2 -d/
}
