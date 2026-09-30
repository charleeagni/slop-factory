import json
import plistlib
import urllib.error
import urllib.request

with open('Resources/Info.plist', 'rb') as source:
    config = plistlib.load(source)
origin = config['SlopFactorySupabaseURL']
assert origin == 'https://toiylcfpbryztcfjievv.supabase.co'
key = config['SlopFactorySupabasePublishableKey']
assert key.startswith('sb_publishable_')

def probe(path, payload=None, profile=None):
    headers = {'apikey': key, 'Content-Type': 'application/json'}
    if profile:
        headers['Accept-Profile'] = profile
    data = None if payload is None else json.dumps(payload).encode()
    request = urllib.request.Request(origin + '/rest/v1/' + path, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            status, body = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, body = error.code, error.read()
    result = json.loads(body)
    code = result.get('code') if isinstance(result, dict) else None
    print(json.dumps({'path': path, 'profile': profile, 'status': status, 'code': code}), flush=True)
    return status, code

status, code = probe('rpc/report_x_activity_v1', {
    'p_grant_id': None, 'p_capability': None,
    'p_disclosure_version': 'x-username-feedback-v1',
    'p_sequence': 0, 'p_handle': 'home',
})
assert status == 400 and code == '22023', 'Report validation gateway failed'
status, code = probe('rpc/withdraw_x_sharing_v1', {
    'p_grant_id': None, 'p_capability': None,
    'p_disclosure_version': 'x-username-feedback-v1',
})
assert status == 400 and code == '22023', 'Withdrawal validation gateway failed'
status, code = probe('rpc/register_x_handle', {'p_handle': 'home'})
assert status in (401, 403, 404) and code != '22023', 'Legacy RPC rejection failed'
for relation in ('sharing_grants', 'acknowledged_handles', 'grant_handles',
                 'username_counts', 'feedback_dm_eligible_handles'):
    for profile in ('x_handle_registry', None):
        status, code = probe(relation + '?limit=0', profile=profile)
        assert status in (401, 403, 404, 406), 'Private relation unexpectedly exposed'
print('PASS: new RPC validation, legacy rejection, all private relation GETs denied')
