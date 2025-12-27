#!/usr/bin/env python3

import json
import requests
import sys

from base64 import b64encode, b64decode
from url_normalize import url_normalize

'''
/usr/share/nwaf/venv/bin/python3 ./wl2erl.py "%LIC. KEY%" "%API BASE URL%" "%PROXY URL%"
%LIC. KEY%          - your lic. key
%API BASE URL%      - API base URL, e.g. https://api.example.com:8080/nw-api/
%PROXY URL%         - proxy-server address (optional)
'''

lic_key = sys.argv[1]
api_base_url = sys.argv[2]
api_proxy = {'http': sys.argv[3], 'https': sys.argv[3]} if (len(sys.argv) > 3) and sys.argv[3] else {}
ua = 'wl2erl converter'

##

def wl2erl():
    try:

        # init
        s = requests.Session()
        s.trust_env = False

        # logging
        print('')
        print('ERL generation for WL begins')
        print('')

        # get WL
        wlr = s.post(
            url_normalize(api_base_url + '/v2/get_dyn_wl'),
            headers={'User-Agent': ua, 'Content-Type': 'application/json'},
            proxies=api_proxy,
            data=json.dumps({'key': lic_key}),
            timeout=30
        )

        # status code processing
        if wlr.status_code not in range(200, 299):
            print('An error occurred while receiving WL: {}'.format(wlr))
            sys.exit(1)

        # result processing
        try:

            # load WL
            wls = json.loads(wlr.content).get('wl', [])

            # skip empty WL
            if not wls:
                print('No WL rules')
                sys.exit(0)

            # get ERL
            erlr = s.post(
                url_normalize(api_base_url + '/v2/get_dyn_erl'),
                headers={'User-Agent': ua, 'Content-Type': 'application/json'},
                proxies=api_proxy,
                data=json.dumps({'key': lic_key}),
                timeout=30
            )

            # status code processing
            if erlr.status_code not in range(200, 299):
                print('An error occurred while receiving ERL: {}'.format(erlr))
                sys.exit(1)

            # load ERL
            try:
                erls = json.loads(erlr.content).get('erl', [])
            except Exception as e:
                print('An error occurred while receiving ERL: {}'.format(e))
                sys.exit(1)

            # WLs processing
            for wl in wls:

                # init
                rid = wl.get('id')
                is_exists = False

                # WL processing
                try:

                    # WL parsing
                    active = wl.get('active')
                    domain = wl.get('domain')
                    rl_id = wl.get('rl_id')
                    mz = wl.get('mz').split('|') if wl.get('mz') else ['url', 'args', 'body', 'headers']
                    extension = wl.get('extension').lstrip('$').split('|$') if wl.get('extension') else []

                    # logging
                    print('  Processing WL {}'.format(rid))

                    # extension normalization
                    r = {}
                    for item in extension:

                        # init
                        k = item.split(':', 1)[0].lower()
                        v = item.split(':', 1)[1]
                        regex = True if k.endswith('_x') else False

                        # remove _x from k
                        k = k.rstrip('_x')

                        # zone normalization
                        k = 'other_headers' if k not in ['url', 'args', 'body', 'cookie', 'referer', 'ua'] else k
                        k = k + '_x' if regex else k
                        del regex

                        # update the result:
                        if k in ['other_headers', 'other_headers_x']:
                            r[k] = [':' + b64encode(v.encode('UTF-8')).decode('UTF-8')]
                        else:
                            r[k] = b64encode(v.encode('UTF-8')).decode('UTF-8')

                    # update the extension
                    extension = r.copy()
                    del r

                    # logging
                    print('   >> Preparing ERL for WL {}'.format(rid))

                    # prepare the ERL
                    erln = {
                        'active': active,
                        'wl': True,
                        'domain': domain,
                        'wl_data': [{rl_id: mz}]
                    }

                    # update ERL with extension
                    if extension:
                        erln = {**erln, **extension}

                    # logging
                    print('   >> Excliding processed ERL for WL {}'.format(rid))

                    # convert new ERL rule to string
                    erll = erln.copy()  # local ERL
                    erll['domain'] = b64encode(erll['domain'].encode('UTF-8')).decode('UTF-8') if erll['domain'] else erll['domain']

                    # skip processed
                    for item in erls:

                        # skip non-wl
                        if not item.get('wl'):
                            continue

                        # init
                        item_id = item.get('id')
                        comp_erl_excl = ['comment']

                        # del excluded field
                        for x in comp_erl_excl:
                            if x in erll:
                                del erll[x]
                            if x in item:
                                del item[x]

                        # ERL normalization
                        item = {x: item[x] for x in erll.keys()}

                        # find processing
                        if str({k: v for k, v in item.items()}) == str({k: v for k, v in erll.items()}):
                            print('   >> ERL {} already exists for WL {}, skipping'.format(item_id, rid))
                            is_exists = True
                            break

                    # skip processing
                    if is_exists:
                        print('')
                        continue

                    # logging
                    print('   >> Generating ERL for WL {}'.format(rid))

                    # create ERL
                    try:

                        # create ERL
                        r = s.post(
                            url_normalize(api_base_url + '/v2/set_dyn_erl'),
                            headers={'User-Agent': ua, 'Content-Type': 'application/json'},
                            proxies=api_proxy,
                            data=json.dumps({'key': lic_key, 'add': erln}),
                            timeout=30
                        )

                        # status processing
                        r = json.loads(r.content)
                        if r.get('status') == 'success':
                            print('   >> ERL {} for WL {} was generated successfully'.format(r.get('id'), rid))
                        else:
                            print('An error occurred while generating ERL for WL {}: {}'.format(rid, r.get('description')))
                            sys.exit(1)

                    except Exception as e:
                        print('An error occurred while generating ERL for WL {}: {}'.format(rid, e))
                        sys.exit(1)

                except Exception as e:
                    print('An error occurred while processing WL {}: {}'.format(rid, e))
                    sys.exit(1)

                # logging
                print('')

        except Exception as e:
            print('An error occurred while processing WL: {}'.format(e))
            sys.exit(1)

    except Exception as e:
        print('An error occurred: {}'.format(e))
        sys.exit(1)

    # logging
    print('ERL for WL generated successfully')
    print('')


## WL to ERL converter
wl2erl()
