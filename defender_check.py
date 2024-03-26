import json
import argparse
import datetime
import requests
from getpass import getpass

def login_compute(base_url, access_key, secret_key):
    url = f"https://{base_url}/api/v1/authenticate"

    payload = json.dumps({"username": access_key, "password": secret_key})
    headers = {"content-type": "application/json; charset=UTF-8"}
    response = requests.post(url, headers=headers, data=payload)
    return response.json()["token"]

def get_defender_data(base_url, token):
    url = f"https://{base_url}/api/v1/defenders"
    payload = {}
    headers = {"content-type": "application/json; charset=UTF-8", "Authorization": "Bearer " + token}
    try:
        response = requests.get(url, headers=headers, data=payload)
        response.raise_for_status()
    except requests.exceptions.RequestException as err:
        print(f"Error in request for Defenders: {err}")
        return None
    
    return response.json()

def parse_defender_data(data):
    scoped_defender_type = ["docker", "cri", "daemonset"]
    # Build list of connected in-scope Defender data
    defender_package = []
    # Capture list of stale, connected Defenders
    stale_defender_info = []
    for item in data:
        defender_type = item['type']
        if item['connected'] == True and defender_type in scoped_defender_type:
            hostname = item['hostname']
            version = item['version']
            image_scan_lastscan = item['status']['image']['scanTime']
            image_scan_is_valid = check_date_range(image_scan_lastscan)
            container_scan_lastscan = item['status']['container']['scanTime']
            container_scan_is_valid = check_date_range(container_scan_lastscan)
            if container_scan_is_valid == False or image_scan_is_valid == False:
                stale_defender_info.append(hostname)
            output_object = json.dumps({"hostname":hostname,"version":version,
                                        "image":image_scan_lastscan,"ImageScanWithin24hr":image_scan_is_valid,
                                        "container":container_scan_lastscan,"ContainerScanWithin24hr":container_scan_is_valid},
                                        indent=4)
            defender_package.append(output_object)
    # Output to console data on stale defenders if they fail the 'within 24hrs' check.
    if len(stale_defender_info) > 0:
        info = json.dumps({"Stale_Defender_Hostnames":stale_defender_info})
        print(info)
    return defender_package

def check_date_range(time_str):
    date_object = datetime.datetime.strptime(time_str, '%Y-%m-%dT%H:%M:%S.%f%z')
    current_datetime = datetime.datetime.now(datetime.UTC)
    time_difference = current_datetime - date_object
    if time_difference < datetime.timedelta(days=1):
        return True
    else:
        return False

def main():
    parser = argparse.ArgumentParser(description="Query PC CWPP for Defenders status and report on discrepancies.")
    parser.add_argument('--url', '-u', type=str, help="Enter TL Console URL; e.g. api.prismacloud.io",required=True)
    parser.add_argument('--identity', '-i', type=str, help="Enter username.", required=True)
    parser.add_argument('--key', '-k', type=str, help="Provide password/key or [optional] enter as secure text")
                        
    args = parser.parse_args()

    identity = args.identity
    # Prompt for the secret key securely if not provided as an argument
    key = args.key if args.key else getpass('Enter your key/password: ')

    api_url = args.url
    token = login_compute(api_url, identity, key)
    
    data = get_defender_data(api_url, token)
    print(f"Object Count: {len(data)}")
    defender_list = parse_defender_data(data)
    # Output to console information for container defenders.
    print(defender_list)

if __name__ == "__main__":
    main()