#!/bin/sh

VERBOSE=0
TOKEN=""
ENDPOINT="images"
FILE_NAME=$(date "+%Y%m%d")
HEADERSTMPFILE="headers.tmp"

#Check requirments
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install it to continue."
    exit 1
fi

while getopts "vt:e:f:c:" opt; do
    case ${opt} in
    v )
    VERBOSE=1
    ;;
    t )
    TOKEN=$OPTARG
    ;;
    e )
    ENDPOINT=$OPTARG
    ;;
    f )
    FILE_NAME=$OPTARG
    ;;
    c )
    CONSOLEURI=$OPTARG
    ;;
    \? )
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
    : )
    #Handle missing arguments
    echo "Option -$OPTARG requires an argument." >&2
    exit 1
    ;;
    esac
done

# Shift off the options so that $1, $2, etc., refer to positional arguments
shift $((OPTIND -1))

# Now you can use the variables in your script logic
echo "Verbose: $VERBOSE"
echo "File Path: $FILE_NAME"
echo "Console URI: $CONSOLEURI"
echo "API Endpoint: $ENDPOINT"

# Access any remaining positional arguments
echo "Remaining arguments: $@"

#Execute curl command and capture the content.
LIMIT=50
DELAY_SECONDS=1 # Delay between requests to respect the rate limit

#echo "Calling curl for $CONSOLEURI and Endpoint $ENDPOINT and will write to $FILE_NAME"

#Make the initial API call and extract headers for response count
curl -s -D $HEADERSTMPFILE -o "$FILE_NAME-offset-0.json" -L "$CONSOLEURI/api/v1/$ENDPOINT?limit=$LIMIT&offset=0" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
if [[ $? > 0 ]]; then
    echo "Initial curl command failed. Exiting..."
    exit 1
fi
TOTALCOUNT=$(cat $HEADERSTMPFILE | grep 'Total-Count' |cut -d':' -f2 |xargs |tr -d '\r')

# Check if we successfully got a number
if [[ -z "$TOTALCOUNT" || ! "$TOTALCOUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: Could not retrieve Total-Count from headers." >&2
    exit 1
fi

echo "Available results: $TOTALCOUNT"
rm -v $HEADERSTMPFILE

# --- Step 2: Conditional Loop for Pagination ---

# Check if the total count is greater than the initial limit
if (( TOTALCOUNT > LIMIT )); then
    echo "More data exists. Starting pagination..."
    
    # Start the loop from the next offset (after the initial LIMIT)
    for ((offset=LIMIT; offset<TOTALCOUNT; offset+=LIMIT)); do
        echo "Fetching data with offset: $offset"
        
        # Perform the curl request and save the response.
        curl -s -o "$FILE_NAME-offset-${offset}.json" -L "$CONSOLEURI/api/v1/$ENDPOINT?limit=$LIMIT&offset=${offset}" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
        
        # Pause to respect the API rate limit
        sleep "$DELAY_SECONDS"
    done
    
    echo "All remaining data fetched."
else
    echo "Total count is less than or equal to the limit. No additional requests needed."
fi

#Filter resulting files for any baseImage information
jq '.[].baseImage | select(. != null)' "$FILE_NAME"-offset*.json