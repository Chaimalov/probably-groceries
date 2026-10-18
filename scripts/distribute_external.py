"""Distribute the processed CI build to the existing Family external group.

Apple may still require beta review. A successful submission is reported as
pending, never as installable. Reruns preserve group membership and metadata.
"""
import json
import os
import urllib.error
import urllib.request

from wait_for_testflight import API, BUNDLE_ID, get, token


def write(method, path, data):
    request = urllib.request.Request(
        API + path, data=json.dumps({"data": data}).encode(), method=method,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=45) as response:
        body = response.read()
        return json.loads(body) if body else None


def relation(resource_type, resource_id):
    return {"data": {"type": resource_type, "id": resource_id}}


def distribute(version):
    apps = get('/v1/apps', {'filter[bundleId]': BUNDLE_ID})['data']
    if len(apps) != 1:
        raise RuntimeError('Could not uniquely resolve Probably Groceries')
    app_id = apps[0]['id']
    result = get(f'/v1/apps/{app_id}/betaGroups', {'limit': '200'})
    if result.get('links', {}).get('next'):
        raise RuntimeError('Group list is paginated; refusing an incomplete lookup')
    groups = [g for g in result['data'] if g['attributes']['name'] == 'Family'
              and not g['attributes']['isInternalGroup']]
    if len(groups) != 1:
        raise RuntimeError('Expected one existing Family external group; no access changed')
    group_id = groups[0]['id']
    builds = get('/v1/builds', {'filter[app]': app_id,
                              'filter[version]': version})['data']
    if len(builds) != 1 or builds[0]['attributes']['processingState'] != 'VALID':
        raise RuntimeError('Expected one valid processed build')
    build_id = builds[0]['id']
    details = get(f'/v1/builds/{build_id}/buildBetaDetail')['data']
    state = details['attributes']['externalBuildState']
    allowed = {'READY_FOR_BETA_SUBMISSION', 'WAITING_FOR_BETA_REVIEW',
               'IN_BETA_REVIEW', 'BETA_APPROVED', 'READY_FOR_BETA_TESTING',
               'IN_BETA_TESTING'}
    if state not in allowed:
        raise RuntimeError(f'External distribution blocked: {state}')

    # Preserve human-written notes. Supply a neutral focus only when absent.
    localizations = get(f'/v1/builds/{build_id}/betaBuildLocalizations')['data']
    notes = os.environ.get('TESTFLIGHT_TEST_NOTES',
                           'בדיקת רשימת הקניות, סנכרון משותף, סימון פריטים והווידג׳טים.')
    hebrew = next((x for x in localizations if x['attributes']['locale'] == 'he'), None)
    if hebrew is None:
        write('POST', '/v1/betaBuildLocalizations', {
            'type': 'betaBuildLocalizations',
            'attributes': {'locale': 'he', 'whatsNew': notes},
            'relationships': {'build': relation('builds', build_id)}})
    elif not (hebrew['attributes'].get('whatsNew') or '').strip():
        write('PATCH', f"/v1/betaBuildLocalizations/{hebrew['id']}", {
            'type': 'betaBuildLocalizations', 'id': hebrew['id'],
            'attributes': {'whatsNew': notes}})
    write('PATCH', f"/v1/buildBetaDetails/{details['id']}", {
        'type': 'buildBetaDetails', 'id': details['id'],
        'attributes': {'autoNotifyEnabled': True}})
    if state == 'READY_FOR_BETA_SUBMISSION':
        write('POST', '/v1/betaAppReviewSubmissions', {
            'type': 'betaAppReviewSubmissions',
            'relationships': {'build': relation('builds', build_id)}})

    assigned = get(f'/v1/builds/{build_id}/betaGroups', {'limit': '200'})
    if group_id not in {g['id'] for g in assigned['data']}:
        # Additive relationship: older builds/testers remain untouched.
        write('POST', f'/v1/betaGroups/{group_id}/relationships/builds',
              [{'type': 'builds', 'id': build_id}])
    state = get(f'/v1/builds/{build_id}/buildBetaDetail')['data']['attributes']['externalBuildState']
    if state in {'BETA_APPROVED', 'READY_FOR_BETA_TESTING'}:
        write('POST', '/v1/buildBetaNotifications', {
            'type': 'buildBetaNotifications',
            'relationships': {'build': relation('builds', build_id)}})

    # Verify the association from the build, including on reruns.
    assigned = get(f'/v1/builds/{build_id}/betaGroups', {'limit': '200'})
    if group_id not in {g['id'] for g in assigned['data']}:
        raise RuntimeError('Family build association was not confirmed')
    attributes = get(f'/v1/builds/{build_id}/buildBetaDetail')['data']['attributes']
    if not attributes['autoNotifyEnabled']:
        raise RuntimeError('Automatic external tester notification was not confirmed')
    state = attributes['externalBuildState']
    if state not in allowed - {'READY_FOR_BETA_SUBMISSION'}:
        raise RuntimeError(f'External submission was not confirmed: {state}')
    status = ('available to Family testers' if state == 'IN_BETA_TESTING'
              else f'assigned to Family; Apple external state={state}; automatic notification enabled')
    summary = f'Build {version}: {status}.\n'
    print(summary, flush=True)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as file:
            file.write(summary)


if __name__ == '__main__':
    try:
        distribute(os.environ['GITHUB_RUN_NUMBER'])
    except urllib.error.HTTPError as error:
        # Never log raw responses, account data, headers, or signing tokens.
        raise SystemExit(f'External TestFlight distribution failed: HTTP {error.code}. '
                         'Check beta review, agreements, and API key permissions in App Store Connect.') from None
