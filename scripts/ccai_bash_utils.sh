GOOGLE_APPLICATION_CREDENTIALS=${1:-~/df-insights-key.json}
AGENT_ID=${2}
PROJECT_ID=${3:-$(gcloud config get-value project)}
#LOCATION_ID=${4:-us-central1}
LOCATION_ID=${4:-global}
LANGUAGE_CODE=en-us
GEP="https://dialogflow.googleapis.com/v2/"
EP="https://${LOCATION_ID}-dialogflow.googleapis.com/v3/"
[[ LOCATION_ID == "global" ]] && EP=$GEP
location="projects/$PROJECT_ID/locations/$LOCATION_ID"
echo > logs/errors.log

gdfcurl() { #use global endpoint otherwise the same as dfcurl
  _EP=$EP ; EP=$GEP
  #echo dfcurl "$@"
  dfcurl "$@"
  EP=$_EP
}


gettoken() {
  #echo gcloud auth application-default print-access-token
  echo gcloud auth print-access-token
}

dfcurl() { # make rest call - args 1 url path past the api base (/projects/...) 2 method 3 data (string or file) 4 file to store the response in    
  [[ -z "$2" ]] && method=""
  [[ -z "$3" ]] && data=""
  [[ -n "$3" ]] && data=" -d '$3'"
  [[ -f "$3" ]] && data=" -d @$3 "
  [[ $2 == "del" ]] && method=" -X DELETE "
  [[ $2 == "get" ]] && method=""
  [[ $2 == "post" ]] && method=" -X POST "
  [[ $2 == "post" && -z $3 ]] && data=' -d "" '
  [[ -z $1 ]] && return

  #echo $1 $method $data ;return
  [[ -n $4 ]] && resp_file="tmp/$4" || resp_file="tmp/resp"
  echo > tmp/request
  echo 'curl -s -H "Authorization: Bearer "$(gcloud auth application-default print-access-token) -H "Content-Type: application/json; charset=utf-8" '$method $data $EP$1 >  tmp/request
  cat tmp/request >> logs/requests.log
  resp="$(source tmp/request)"
  echo "$resp"
  echo "$resp"> "$resp_file"
}

list_agents() { # list any agents in the project (-r will print the json) 
	[[ $1 = "-r" ]] && dfcurl ${location}/agents && return
	 dfcurl ${location}/agents | jq -r '.agents[]|[.displayName,(.name|split("/"))[-1]]|@tsv' 2>>logs/errors.log
}

start_conv() { # starts a new conversation return conversation id (convid)
  cp="";convid=""
  [[ -n $1 ]] && cp="$(list_conv_profiles | grep "$1" | awk '{printf $NF}' | tail -1 2>/dev/null)" \
  || cp="$(list_conv_profiles | awk ' {printf $NF}' 2>/dev/null| tail -1 2>/dev/null)"
  [[ -z $cp ]] && echo "can't find conversation profile" && return

  pl='{"conversationProfile":"'$cp'"}'
  convid=$(gdfcurl "projects/$PROJECT_ID/conversations/" post "$pl" | jq -r '.name')
  echo $convid
}

add_participant() { #add participents to the conersation (convid)
  [[ -z $1 ]] && echo "missing conversation id" && return
  #gdfcurl $1/participants post '{ "role": "END_USER", }'
  partid=$(gdfcurl $1/participants post '{ "role": "END_USER", }' | jq -r '.name')
  echo $partid
}

list_participants() { # list participents for the conversation - args 1 (convid) 
  [[ -z $1 ]] && echo "missing conversation id" && return
  partids="$(gdfcurl $1/participants | jq '.participants[].name' 2>/dev/null)"
  [[ -z $partids ||  $partids == "null" ]] ||echo "$partids"
}

list_conv_profiles() { #list conversation profiles
  [[ $1 == "-r" ]] && dfcurl projects/$PROJECT_ID/conversationProfiles && return
  #dfcurl projects/$PROJECT_ID/conversationProfiles | jq -r '.conversationProfiles[]|[.displayName,(.name|split("/"))[-1]]|@tsv'
  profiles=$(gdfcurl projects/$PROJECT_ID/conversationProfiles | jq -r '.conversationProfiles[]|[.displayName,.name]|@tsv ' 2>/dev/null)
  echo "$profiles"
}

create_conv_profile() { # creates conevrsation profile
  [[ -n $1 ]] && [[ -f $1 ]] && pl=$1
  [[ -n $1 ]] && [[ ! -f $1 ]] && _pl='{"displayName":"__"}' && pl=${_pl/__/$1}
  [[ -z $1 ]] && pl='{"displayName":"Test Conversation Profile"}'
  profile="$(gdfcurl projects/$PROJECT_ID/conversationProfiles post "$pl" | jq -r '.name' 2>/dev/null)"
  echo "$profile"
}

delete_conv_profile() { #delete conversation profile
  cids=$(list_conv_proviles | awk '/'$1'/ {printf $NF" "}' 2>/dev/null)
  [[ -z $cids ]] && echo "Can't get agent ids for $1" && return
  for cid in $cids
  do
    echo "deleting $cid"
    gdfcurl projects/$PROJECT_ID/conversationProfiles/$cid del
  done
}

chat() { # analyze content of text input expect 1-url(to participant id) and any number of  of texts
   [[ -z $1 ]] && echo "missing participant id" && return
   url="$1" ; shift
   for t in "$@"
   do
	echo "$t"
	resp="$(gdfcurl "$url:analyzeContent" post '{ "textInput": { "text": "'"$t"'" , "languageCode": "en-US" } }')"
        echo "$resp" >> tmp/requests.log
  done
}

list_convs() { # list ongoing conevrsations 
  [[ -n $1 ]] && convs="$(gdfcurl "projects/$PROJECT_ID/conversations/" |jq -r '.conversations[]|select(.conversationProfile|test("'$1'"))|[.name,.conversationProfile,lifecycleState]|@tsv' 2>/dev/null)" || \
  convs="$(gdfcurl "projects/$PROJECT_ID/conversations/" | jq '.conversations[]|select(.lifecycleState != "COMPLETED")|.name' 2>/dev/null)"
  [[ ! "$convs" == "null" ]] && echo "$convs"
}

saySomething() { # creates eevrything you need to trigger text flowing to insights, expext text
  convid="";partid="";profile=""
  profiles=$(list_conv_profiles | tail -1 2>/dev/null)
  if [[ -z $profiles ]]; then
    echo "Creating new profile"
    profile=$(create_conv_profile )
  else
    profile="$(echo "$profiles" | awk '{print $NF}' | tail -1)"
    echo "Using first profile found $profile"
  fi
  [[ -z $profile ]] && echo could not create profile && return
  convid=$(list_convs | tail -1 2>/dev/null)
  [[ -z $convid ]] && echo starting a conversation && convid="$(start_conv $profile)" || echo continuing an ongoing conversation conversation $convid
  [[ -z $convid ]] && echo "Could not find or start a conversation" && return
  echo looking for participants for the conversation
  partid="$(list_participants $convid | tail -1 2>/dev/null)"
  [[ -z $partid ]] && echo adding participant && partid="$(add_participant $convid)" || echo "speaking as existing participant"
  [[ -z $partid ]] && echo cant add participant && return
  echo lets chat...
  chat "$partid" "$@"

}

sayAnotherThing() { # if you already have a conversation - you can add text to it with this.
  chat "$partid" "$@"
}

complete_all_conv() { # complete conevrsations - this is needed for data to pass to insights. 
  for c in $(list_convs)
  do
    gdfcurl ${c}:complete post
  done
}

detectIntent() { # call detect intent on the text
  uuid=$(uuidgen)
  for t in "$@"
  do
    dfcurl $agent/environments/draft/sessions/$uuid:detectIntent post '{"queryInput": { "languageCode":"'"$LANGUAGE_CODE"'","text":{ "text":"'"$t"'"}}}'
  done
}

create_agent() { # create an agent, expect 1 agent name 2 - language, 3 timezone - has default for all 
      rm tmp/create_agent_resp 2>/dev/null
      agent="${1:-testAgent}"
      lc="${2:-$LANGUAGE_CODE}"
      tz="${3:-America/Los_Angeles}"
      echo "creating agent $agent language $lc timezone $tz "
      dfcurl "$location/agents" post '{"displayName":"'$agent'","defaultLanguageCode":"'$lc'","timeZone":"'$tz'"}' create_agent_resp
}

import_agent() { # create an agent and import base64 encoded file (restore) expet 1 - file (required) ,2 name 
      rm tmp/payload 2>/dev/null
      if [[ -z $import_agent_id ]]; then
        create_agent ${2} # doing this so we can retry
        import_agent_id="$(cat tmp/create_agent_resp| jq -r '.name')"
        export import_agent_id=${import_agent_id//*\/}
      fi
      [[ $(list_agents | grep -c $import_agent_id ) -lt 1 ]] && echo "could not create agent" && return 1
      [[ -f $1 ]] && echo '{"agentContent":"'"$(cat $1)"'"}'> tmp/payload ||  echo "must provide agent content to import"
      [[ -f tmp/payload ]] && dfcurl "$location/agents/${import_agent_id}:restore" post tmp/payload 
}

yesno() { # promot with y/n args: 1-text 
    cont=0
    while [[ $cont == 0 ]]
    do
      read -p "${1} (y/n): "  -N 1 prompt
      echo
      [[ ${prompt,,} == "y" || ${prompt,,} == "n" ]] && cont=1 || echo "$prompt not valid selection choose  y/n"
    done
}

f() { #list all functions in this file with description
   awk '/\(\)/ {sub(/\(\) \{/,"");split($0,a,"#");printf "%-20s : %s\n",a[1],a[2]}' ${BASH_SOURCE[0]} | sed 's/:\s*/: /g' 
}

# This is where the main starts...

[[ -z $AGENT_ID ]] && AGENT_ID="$(list_agents | head -1 | awk '{print $NF}')"
agent="$location/agents/$AGENT_ID"
echo AGENT_ID "$AGENT_ID" PROJECT_ID $PROJECT_ID LOCATION_ID $LOCATION_ID LANGUAGE_CODE $LANGUAGE_CODE 




if [[ -z $AGENT_ID ]];then 
    echo "You must have at least one agent created" 
    yesno "Create a sample agent in pacific time en-us (financial services)?"
    [[ ${prompt,,} == "y" ]] &&  import_agent agents/finserv_agent.b64 
fi


