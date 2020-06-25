#!/bin/sh -l

TOKEN="$INPUT_ORG_TOKEN"
ORG_NAME="$INPUT_ORG_NAME"
ACTOR="$INPUT_ACTOR"
ASSIGNEES=$(echo $INPUT_ASSIGNEES | jq -r .[])

function add_section() {
  let section_count++
  echo -e "\n>>> ${section_count}. $1\n"
}

if [ -z "$TOKEN" ]; then
  echo "TOKEN is not defined." >&2
  exit 1
fi
if [ -z "$ORG_NAME" ]; then
  echo "ORG_NAME is not defined." >&2
  exit 1
fi
if [ -z "$ACTOR" ]; then
  echo "ACTOR is not defined." >&2
  exit 1
fi
if [ -z "$ASSIGNEES" ]; then
  echo "ASSIGNEES is not defined." >&2
  exit 1
fi

find_project_id() {
  _PROJECT_TYPE="$1"
  _PROJECT_URL="$2"

  case "$_PROJECT_TYPE" in
    org)
      _ORG_NAME=$ORG_NAME
      _ENDPOINT="https://api.github.com/orgs/$_ORG_NAME/projects"
      ;;
    user)
      _USER_NAME=$(echo "$_PROJECT_URL" | sed -e 's@https://github.com/users/\([^/]\+\)/projects/[0-9]\+@\1@')
      _ENDPOINT="https://api.github.com/users/$_USER_NAME/projects"
      ;;
    repo)
      _ENDPOINT="https://api.github.com/repos/$GITHUB_REPOSITORY/projects"
      ;;
  esac

  _PROJECTS=$(curl -s -X GET -u "$ACTOR:$TOKEN" --retry 3 \
           -H 'Accept: application/vnd.github.inertia-preview+json' \
           "$_ENDPOINT")

  _PROJECTID=$(echo -n "$_PROJECTS" | jq -r ".[] | select(.html_url == $_PROJECT_URL).id")

  if [ "$_PROJECTID" != "" ]; then
    echo "$_PROJECTID"
  else
    echo "No project was found." >&2
    exit 1
  fi

  unset _PROJECT_TYPE _PROJECT_URL _ORG_NAME _USER_NAME _ENDPOINT _PROJECTS _PROJECTID
}

find_column_id() {
  _PROJECT_ID="$1"
  _INITIAL_COLUMN_NAME="$2"

  _COLUMNS=$(curl -s -X GET -u "$ACTOR:$TOKEN" --retry 3 \
          -H 'Accept: application/vnd.github.inertia-preview+json' \
          "https://api.github.com/projects/$_PROJECT_ID/columns")

  echo "$_COLUMNS" | jq -r ".[] | select(.name == \"$_INITIAL_COLUMN_NAME\").id"
  unset _PROJECT_ID _INITIAL_COLUMN_NAME _COLUMNS
}

INITIAL_COLUMN_NAME="$INPUT_COLUMN_NAME"
if [ -z "$INITIAL_COLUMN_NAME" ]; then
  # assing the column name by default
  INITIAL_COLUMN_NAME='To do'
  if [ "$GITHUB_EVENT_NAME" == "pull_request" ]; then
    echo "changing col name for PR event"
    INITIAL_COLUMN_NAME='In progress'
  fi
fi

TARGET_PROJECTS=$(curl -s -X GET -u "$ACTOR:$TOKEN" --retry 3 \
  -H "Accept: application/vnd.github.inertia-preview+json" \
  "https://api.github.com/orgs/${ORG_NAME}/projects" | \
  jq '.[] | select( .body | contains("KANBAN") ) | { name: .name, desc: .body, url: .html_url }' | jq -s)

len=$(echo $TARGET_PROJECTS | jq length)

for i in $( seq 0 $(($len - 1)) )
do
  CURRENT_PROJECT=$(echo $TARGET_PROJECTS | jq .[${i}])
  TARGET_TEAM=$(echo $CURRENT_PROJECT | jq .desc | cut -d '*' -f 3 | cut -d ':' -f 2)
  add_section "got target team"

  MEMBERS=$(curl -s -X GET -u "$ACTOR:$TOKEN" --retry 3 \
    -H "Content-Type: application/json" \
    "https://api.github.com/orgs/${ORG_NAME}/teams/${TARGET_TEAM}/members" | jq .[].login)
  add_section "got target team members"



  if [ "`echo $MEMBERS | grep $ASSIGNEES`" ]; then
    add_section "The person assigned this time was included in the target team"

    PROJECT_URL=$(echo $CURRENT_PROJECT | jq .url)
    # TODO: handle any project type
    PROJECT_TYPE=org
    PROJECT_ID=$(find_project_id "$PROJECT_TYPE" "$PROJECT_URL")
    INITIAL_COLUMN_ID=$(find_column_id $PROJECT_ID "${INITIAL_COLUMN_NAME:?<Error> required this environment variable}")

		case "$GITHUB_EVENT_NAME" in
			issues)
				ISSUE_ID=$(jq -r '.issue.id' < "$GITHUB_EVENT_PATH")

				# Add this issue to the project column
				curl -s -X POST -u "$GITHUB_ACTOR:$TOKEN" --retry 3 \
				 -H 'Accept: application/vnd.github.inertia-preview+json' \
				 -d "{\"content_type\": \"Issue\", \"content_id\": $ISSUE_ID}" \
				 "https://api.github.com/projects/columns/$INITIAL_COLUMN_ID/cards"
				;;
			pull_request)
				PULL_REQUEST_ID=$(jq -r '.pull_request.id' < "$GITHUB_EVENT_PATH")

				# Add this pull_request to the project column
				curl -s -X POST -u "$GITHUB_ACTOR:$TOKEN" --retry 3 \
				 -H 'Accept: application/vnd.github.inertia-preview+json' \
				 -d "{\"content_type\": \"PullRequest\", \"content_id\": $PULL_REQUEST_ID}" \
				 "https://api.github.com/projects/columns/$INITIAL_COLUMN_ID/cards"
				;;
			*)
				echo "Nothing to be done on this action: $GITHUB_EVENT_NAME" >&2
				exit 1
				;;
		esac
  fi
  unset section_count
done
