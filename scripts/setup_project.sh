#!/usr/bin/env bash
# set -x


echo > logs/error.log
[[ -n $1 ]] && PROJECT_ID=$1 || PROJECT_ID="$(gcloud config get-value project)"
REGION=${2:-global}
DFSA=${3:-df-insights-integration-sa}
echo "project $PROJECT_ID"
[[ -z $PROJECT_ID ]] && echo "ERROR: Project must be set, either past as a parameter or have gcloud activated" && exit 1
if [[ "$(gcloud projects list | grep "$PROJECT_ID")" =~  "$PROJECT_ID" ]]; then 
    echo setting up integration for dialog flow with $PROJCET_ID
    echo adding service account $DFSA
else 
    echo "project $PROJECT_ID was not found"
    exit 1
fi
source reset-policies.sh $PROJECT_ID  2>logs/error.log 1logs/stdout.log

prepare_project() {
	if [[ -n $PROJECT_ID ]]; then

	gcloud iam service-accounts create $DFSA --description "Service account for dialog flow runtime to export conversation to insights" --display-name "$DFSA" 2>logs/error.log 1logs/stdout.log
	echo -n "waiting for sa to be created.."
	while [[ -z $sa ]]
	do
	    sa=$(gcloud iam service-accounts list --format json | jq -r '.[]|select(.displayName|test("'$DFSA'"))|.email') 2>logs/error.log 1logs/stdout.log
	    sleep 1
        echo -n .
	done
	echo done..sa=$sa
	export sa
	echo adding dialogflow role
	gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$sa" --role="roles/dialogflow.admin" 2>logs/error.log 1logs/stdout.log >/dev/null
	echo getting key for sa
	echo "waiting for pilicy changes to take effect..."
    while [[ ! -f  ~/df-insights-key.json ]]
    do
        gcloud iam service-accounts keys create ~/df-insights-key.json --iam-account=$sa 2>logs/error.log 1logs/stdout.log >/dev/null
        sleep 5
        echo -n .
    done
	echo -n calling dialog flow end point to enable the integration using service account key..
	export GOOGLE_APPLICATION_CREDENTIALS=~/df-insights-key.json
	return 0

else 
	echo "no valid PROJECT ID or SERVICE ACCOUNT"
	return 1
fi
}

enable_services() {
  cat demo_services.txt | xargs echo gcloud service enable 
  
}
reset_inherited_policies "$PROJECT_ID" 2>logs/error.log 1logs/stdout.log
enable_services &&  prepare_project 

#this seems to not be available anymore, neable in the console.
#enable_integration

# enable_integration() {
# 	echo  PATCH https://dialogflow.googleapis.com/v2beta1/projects/$PROJCET_ID/locations/$REGION/securitySettings?update_mask=insights_export_settings
# 	echo "Enabling integration"
# 	curl -H "Content-Type: application/json" \
# 	     -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
# 	     PATCH https://dialogflow.googleapis.com/v2beta1/projects/$PROJCET_ID/locations/${REGION}/securitySettings?update_mask=insights_export_settings \
#      --data '{"insights_export_settings": {"enable_insights_export": true}}'
# }
