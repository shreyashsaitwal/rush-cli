#!/usr/bin/env python3
import json
import os
import sys
import zipfile

USAGE = 'usage: mkproject.py <project-dir> <aix>...'
PACKAGE = 'dev.rush.e2e.Smoke'


def install_extensions(project, aixes):
    components = []
    target = os.path.join(project, 'assets', 'external_comps')
    for aix in aixes:
        with zipfile.ZipFile(aix) as zf:
            zf.extractall(target)
            for name in zf.namelist():
                if name.endswith('/components.json'):
                    components += json.loads(zf.read(name))
    return components


def form_json(components):
    instances = [{
        '$Name': f'{c["name"]}1',
        '$Type': c['name'],
        '$Version': c['version'],
        'Uuid': str(i + 1),
    } for i, c in enumerate(components)]
    return {
        'authURL': ['ai2.appinventor.mit.edu'],
        'YaVersion': '230',
        'Source': 'Form',
        'Properties': {
            '$Name': 'Screen1', '$Type': 'Form', '$Version': '31',
            'AppName': 'Smoke', 'Title': 'Smoke', 'Uuid': '0',
            '$Components': instances,
        },
    }


def yail(components):
    adds = '\n'.join(f'(add-component Screen1 {c["type"]} {c["name"]}1 )' for c in components)
    return f'''#|
$Source $Yail
|#

(define-form {PACKAGE}.Screen1 Screen1 #f)
(require <com.google.youngandroid.runtime>)
(do-after-form-creation (set-and-coerce-property! 'Screen1 'AppName "Smoke" 'text))
{adds}
(init-runtime)
'''


def main(project, *aixes):
    components = install_extensions(project, aixes)
    source = os.path.join(project, 'src', *PACKAGE.split('.'))
    os.makedirs(source, exist_ok=True)
    os.makedirs(os.path.join(project, 'youngandroidproject'), exist_ok=True)
    with open(os.path.join(project, 'youngandroidproject', 'project.properties'), 'w') as f:
        f.write(f'main={PACKAGE}.Screen1\nname=Smoke\nassets=../assets\nsource=../src\nbuild=../build\n'
                'versioncode=1\nversionname=1.0\nuseslocation=False\naname=Smoke\nsizing=Responsive\n'
                'showlistsasjson=True\ntheme=AppTheme.Light.DarkActionBar\n')
    with open(os.path.join(source, 'Screen1.scm'), 'w') as f:
        f.write(f'#|\n$JSON\n{json.dumps(form_json(components))}\n|#\n')
    with open(os.path.join(source, 'Screen1.bky'), 'w') as f:
        f.write('<xml xmlns="http://www.w3.org/1999/xhtml"></xml>\n')
    with open(os.path.join(source, 'Screen1.yail'), 'w') as f:
        f.write(yail(components))
    print(', '.join(c['type'] for c in components))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(USAGE)
    main(*sys.argv[1:])
